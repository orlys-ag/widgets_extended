/// Where a drop over a frozen band lands: the window rules a placement is
/// resolved on, and the port's two-lattice sample they read.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_drag_controller.dart';
import 'package:widgets_extended/board/board_views.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

Widget? _nullCell(BuildContext context, BoardCellView<String, _Item> cell) {
  return null;
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  required BoardAxisConfig rows,
  BoardAxisConfig? columns,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: rows,
    columns: columns ?? BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _frame(Widget board, {double width = 280.0, double height = 300.0}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: _frameKey,
          width: width,
          height: height,
          child: board,
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

/// A sample whose visible bounds and track count are the only fields a
/// window reads.
BoardAxisSample _bounds({
  double? visibleFrom,
  double? visibleTo,
  int trackCount = 30,
}) {
  return (
    painted: 0.0,
    paintedExtended: 0.0,
    scrolled: 0.0,
    scrollPixels: 0.0,
    band: null,
    visibleFrom: visibleFrom,
    visibleTo: visibleTo,
    trackCount: trackCount,
    leadingBandEnd: 0,
    trailingBandStart: trackCount,
  );
}

({int start, int end})? _holding(double start, double end) {
  return bandHolding(
    start,
    end,
    leadingBandEnd: 1,
    trailingBandStart: 29,
    trackCount: 30,
  );
}

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

Widget _plainCell(BuildContext context, BoardCellView<String, _Item> cell) {
  return ColoredBox(
    color: cell.isFrozen ? const Color(0xFF2196F3) : const Color(0xFFE0E0E0),
  );
}

Widget _plainItem(BuildContext context, BoardItemView<String, _Item> item) {
  return ColoredBox(key: _itemKey(item.key), color: const Color(0xFF4CAF50));
}

/// A painted rect equal to [expected] up to rounding in the geometry.
void _expectRect(Rect? actual, Rect expected) {
  expect(actual, isNotNull);
  expect(actual!.left, closeTo(expected.left, 1e-9));
  expect(actual.top, closeTo(expected.top, 1e-9));
  expect(actual.width, closeTo(expected.width, 1e-9));
  expect(actual.height, closeTo(expected.height, 1e-9));
}

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

/// A drag harness: a board of [items] (the dragged one is "m"), scrolled
/// to [verticalScroll] and [horizontalScroll], and a drag controller
/// driven directly whose `onItemMoved` records and applies each report,
/// and whose `canDropAt`, when given, is also recorded in [asked]. With
/// [resize], the config admits both primary-axis resize edges and its
/// `onItemResized` records and applies each report.
typedef _Setup = ({
  BoardController<String, _Item> controller,
  RenderBoardViewport<String> viewport,
  BoardDragController<String> drag,
  List<BoardSpan> moves,
  List<BoardSpan> asked,
  List<BoardSpan> resizes,
});

Future<_Setup> _setup(
  WidgetTester tester, {
  required BoardAxisConfig rows,
  BoardAxisConfig? columns,
  required Map<String, BoardSpan> items,
  BoardCellBuilder<String, _Item> cellBuilder = _nullCell,
  double verticalScroll = 0.0,
  double horizontalScroll = 0.0,
  ScrollableDetails verticalDetails = const ScrollableDetails.vertical(),
  BoardSnap snap = const BoardSnap.track(),
  double autoScrollEdgeZone = 0.0,
  BoardDropFit? dropFit,
  bool Function(
    BoardController<String, _Item> controller,
    String key,
    BoardSpan span,
  )?
  canDropAt,
  bool resize = false,
}) async {
  final controller = _controller(tester, rows: rows, columns: columns);
  for (final entry in items.entries) {
    controller.addItem(_Item(entry.key), entry.value);
  }
  await tester.pumpWidget(
    _frame(
      Board<String, _Item>(
        controller: controller,
        verticalDetails: verticalDetails,
        cellBuilder: cellBuilder,
        itemBuilder: _plainItem,
      ),
    ),
  );
  final viewport = _viewport(tester);
  if (verticalScroll != 0.0) {
    viewport.verticalPosition!.jumpTo(verticalScroll);
  }
  if (horizontalScroll != 0.0) {
    viewport.horizontalPosition!.jumpTo(horizontalScroll);
  }
  await tester.pump();
  final moves = <BoardSpan>[];
  final asked = <BoardSpan>[];
  final resizes = <BoardSpan>[];
  final drag = BoardDragController<String>(
    boardController: controller,
    vsync: tester,
    config: BoardDragConfig<String>(
      snap: snap,
      autoScrollEdgeZone: autoScrollEdgeZone,
      dropFit: dropFit,
      canDropAt: canDropAt == null
          ? null
          : (key, span) {
              asked.add(span);
              return canDropAt(controller, key, span);
            },
      onItemMoved: (key, span) {
        moves.add(span);
        controller.moveItem(key, span);
      },
      primaryResizeEdges: resize
          ? BoardResizeEdges.both
          : BoardResizeEdges.none,
      onItemResized: resize
          ? (key, span) {
              resizes.add(span);
              controller.resizeItem(key, span);
            }
          : null,
    ),
  );
  addTearDown(drag.dispose);
  addTearDown(() {
    drag.endDrag(cancel: true);
  });
  return (
    controller: controller,
    viewport: viewport,
    drag: drag,
    moves: moves,
    asked: asked,
    resizes: resizes,
  );
}

void _lift(WidgetTester tester, _Setup s, Offset local) {
  expect(
    s.drag.startDrag(
      key: "m",
      renderPort: s.viewport,
      pointerGlobal: _global(tester, local),
    ),
    isTrue,
  );
}

/// Starts a resize of "m"'s [edge] on the row axis, the primary one.
void _liftEdge(
  WidgetTester tester,
  _Setup s,
  Offset local,
  BoardResizeEdges edge,
) {
  expect(
    s.drag.startDrag(
      key: "m",
      renderPort: s.viewport,
      pointerGlobal: _global(tester, local),
      edge: edge,
      axis: Axis.vertical,
    ),
    isTrue,
  );
}

void _update(WidgetTester tester, _Setup s, Offset local) {
  s.drag.updateDrag(_global(tester, local));
}

Future<void> _commit(WidgetTester tester, _Setup s) async {
  s.drag.endDrag(cancel: false);
  await tester.pumpAndSettle();
}

/// Refuses a span that any other item overlaps, read through `itemsIn`.
bool _noOverlap(
  BoardController<String, _Item> controller,
  String key,
  BoardSpan span,
) {
  for (final other in controller.itemsIn(
    span.rowStart,
    span.endTrackOn(Axis.vertical).ceil(),
    span.colStart,
    span.endTrackOn(Axis.horizontal).ceil(),
  )) {
    if (other == key) {
      continue;
    }
    final o = controller.spanOf(other)!;
    final rowsMeet =
        span.startTrackOn(Axis.vertical) < o.endTrackOn(Axis.vertical) &&
        o.startTrackOn(Axis.vertical) < span.endTrackOn(Axis.vertical);
    final colsMeet =
        span.startTrackOn(Axis.horizontal) < o.endTrackOn(Axis.horizontal) &&
        o.startTrackOn(Axis.horizontal) < span.endTrackOn(Axis.horizontal);
    if (rowsMeet && colsMeet) {
      return false;
    }
  }
  return true;
}

BoardAxisConfig _rows({int frozenStart = 0, int frozenEnd = 0}) {
  return BoardAxisConfig(
    axis: UniformAxis(30, 50.0),
    frozenStart: frozenStart,
    frozenEnd: frozenEnd,
  );
}

const BoardSpan _m25 = BoardSpan(rowStart: 25, colStart: 1);

void main() {
  group("the window functions", () {
    test("firstGridStartAbove(20.0, 1.0)", () {
      expect(firstGridStartAbove(20.0, 1.0), 21.0);
    });
    test("firstGridStartAbove(20.2, 1.0)", () {
      expect(firstGridStartAbove(20.2, 1.0), 21.0);
    });
    test("firstGridStartAbove(20.0 - 1e-12, 1.0)", () {
      expect(firstGridStartAbove(20.0 - 1e-12, 1.0), 21.0);
    });
    test("firstGridStartAbove(20.2, 0.25)", () {
      expect(firstGridStartAbove(20.2, 0.25), 20.25);
    });

    test("lastGridStartBelow(5.0, 1.0)", () {
      expect(lastGridStartBelow(5.0, 1.0), 4.0);
    });
    test("lastGridStartBelow(5.3, 1.0)", () {
      expect(lastGridStartBelow(5.3, 1.0), 5.0);
    });
    test("lastGridStartBelow(5.0 + 1e-12, 1.0)", () {
      expect(lastGridStartBelow(5.0 + 1e-12, 1.0), 4.0);
    });

    test("scrolledWindowOf, visibleFrom 21.0 alone", () {
      expect(
        scrolledWindowOf(_bounds(visibleFrom: 21.0), 1.0, 1.0),
        (min: 21.0, max: 29.0),
      );
    });
    test("scrolledWindowOf, visibleTo 5.0 alone", () {
      expect(
        scrolledWindowOf(_bounds(visibleTo: 5.0), 1.0, 1.0),
        (min: 0.0, max: 4.0),
      );
    });
    test("scrolledWindowOf, neither bound", () {
      expect(scrolledWindowOf(_bounds(), 1.0, 1.0), (min: 0.0, max: 29.0));
    });
    test("scrolledWindowOf, equal bounds 21.0 with extent 2", () {
      expect(
        scrolledWindowOf(
          _bounds(visibleFrom: 21.0, visibleTo: 21.0),
          2.0,
          1.0,
        ),
        isNull,
      );
    });
    test("scrolledWindowOf, bounds 21.5 and 21.7 with extent 0.25", () {
      expect(
        scrolledWindowOf(
          _bounds(visibleFrom: 21.5, visibleTo: 21.7),
          0.25,
          1.0,
        ),
        isNull,
      );
    });

    test("bandWindowOf, band (0, 1) with extent 1", () {
      expect(bandWindowOf((start: 0, end: 1), 1.0), (min: 0.0, max: 0.0));
    });
    test("bandWindowOf, band (0, 1) with extent 2", () {
      expect(bandWindowOf((start: 0, end: 1), 2.0), isNull);
    });
    test("bandWindowOf, band (29, 30) with extent 1", () {
      expect(bandWindowOf((start: 29, end: 30), 1.0), (min: 29.0, max: 29.0));
    });

    test("bandHolding [0, 1)", () {
      expect(_holding(0.0, 1.0), (start: 0, end: 1));
    });
    test("bandHolding [0, 1 + 1e-12)", () {
      expect(_holding(0.0, 1.0 + 1e-12), (start: 0, end: 1));
    });
    test("bandHolding [0, 1.02)", () {
      expect(_holding(0.0, 1.02), isNull);
    });
    test("bandHolding [29, 30)", () {
      expect(_holding(29.0, 30.0), (start: 29, end: 30));
    });
    test("bandHolding [28.99, 30)", () {
      expect(_holding(28.99, 30.0), isNull);
    });
    test("boundedScrolled over the scrolled region", () {
      expect(
        boundedScrolled(4.6, painted: 4.0, band: null, leadingBandEnd: 1),
        4.0,
      );
    });
    test("boundedScrolled over the leading band", () {
      expect(
        boundedScrolled(
          -0.2,
          painted: 0.6,
          band: (start: 0, end: 1),
          leadingBandEnd: 1,
        ),
        0.6,
      );
      expect(
        boundedScrolled(
          20.5,
          painted: 0.6,
          band: (start: 0, end: 1),
          leadingBandEnd: 1,
        ),
        20.5,
      );
    });
    test("boundedScrolled over a trailing band", () {
      expect(
        boundedScrolled(
          5.0,
          painted: 4.0,
          band: (start: 4, end: 5),
          leadingBandEnd: 0,
        ),
        4.0,
      );
      expect(
        boundedScrolled(
          3.0,
          painted: 4.2,
          band: (start: 4, end: 5),
          leadingBandEnd: 0,
        ),
        3.0,
      );
    });
    test("boundedScrolled over a trailing band that starts at track 0", () {
      expect(
        boundedScrolled(
          2.0,
          painted: 1.0,
          band: (start: 0, end: 30),
          leadingBandEnd: 0,
        ),
        1.0,
      );
    });
  });

  testWidgets(
    "a band that fills the viewport gives both visible bounds, equal",
    (tester) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 6),
      );
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(controller: controller, cellBuilder: _nullCell),
        ),
      );
      final viewport = _viewport(tester);
      // Setup sanity: the band leaves no scrolled region.
      expect(viewport.scrolledRegion.height, 0.0);
      final row = viewport.trackSampleAt(const Offset(60.0, 100.0))!.row;
      // TARGET.
      expect(row.visibleFrom, 6.0);
      expect(row.visibleTo, 6.0);
    },
  );

  testWidgets("a trailing band that covers the whole axis pins trailing", (
    tester,
  ) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenEnd: 30),
    );
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 29, colStart: 1),
    );
    // Setup sanity: the trailing band starts at track 0.
    expect(controller.rows.trailingBandStart, 0);
    expect(controller.rows.leadingBandEnd, 0);
    // TARGET.
    expect(
      controller.pinOfId(controller.idOfKey("m"), Axis.vertical),
      BoardPin.trailing,
    );
  });

  group("moves over a band", () {
    testWidgets("T1 a track-snap corner in the header's lower half lands "
        "in the first row that shows", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": _m25},
        verticalScroll: 1000.0,
      );
      // Setup sanity.
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 250.0, 40.0, 50.0),
      );
      expect(
        s.viewport.trackSpaceAt(const Offset(40.0, 35.0))!.row,
        closeTo(0.7, 1e-9),
      );
      _lift(tester, s, const Offset(60.0, 275.0));
      _update(tester, s, const Offset(60.0, 60.0));
      // TARGET.
      expect(s.drag.currentTarget!.span.rowStart, 21);
      await _commit(tester, s);
      // TARGET: the committed item paints in the viewport.
      expect(s.viewport.rectOfItem("m")!.top, 50.0);
    });

    testWidgets("T2 a free-snap proxy mostly over the header pins there", (
      tester,
    ) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": _m25},
        verticalScroll: 1000.0,
        snap: const BoardSnap.free(),
      );
      _lift(tester, s, const Offset(60.0, 275.0));
      _update(tester, s, const Offset(60.0, 45.0));
      // TARGET.
      expect(
        s.drag.currentTarget!.span,
        const BoardSpan(rowStart: 0, colStart: 1),
      );
      await _commit(tester, s);
      // TARGET.
      expect(s.viewport.rectOfItem("m")!.top, 0.0);
    });

    testWidgets("T3 a free-snap proxy mostly below the header scrolls", (
      tester,
    ) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": _m25},
        verticalScroll: 1000.0,
        snap: const BoardSnap.free(),
      );
      _lift(tester, s, const Offset(60.0, 275.0));
      _update(tester, s, const Offset(60.0, 60.0));
      final span = s.drag.currentTarget!.span;
      // TARGET.
      expect(span.rowStart, 20);
      expect(span.rowFraction, closeTo(0.7, 1e-9));
      await _commit(tester, s);
      // TARGET.
      expect(s.viewport.rectOfItem("m")!.top, 35.0);
    });

    testWidgets("T4 a quarter-snap proxy mostly over the header pins "
        "there", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": _m25},
        verticalScroll: 1000.0,
        snap: const BoardSnap.fraction(0.25),
      );
      _lift(tester, s, const Offset(60.0, 275.0));
      _update(tester, s, const Offset(60.0, 45.0));
      // TARGET.
      expect(
        s.drag.currentTarget!.span,
        const BoardSpan(rowStart: 0, colStart: 1),
      );
    });

    testWidgets("T5 a two-row item over a three-row header lands inside "
        "it", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 3),
        items: {"m": const BoardSpan(rowStart: 25, colStart: 1, rowSpan: 2)},
        verticalScroll: 1000.0,
      );
      _lift(tester, s, const Offset(60.0, 275.0));
      _update(tester, s, const Offset(60.0, 110.0));
      // Setup sanity: the proxy's corner reads 1.7 in the header.
      expect(
        s.viewport.trackSpaceAt(const Offset(40.0, 85.0))!.row,
        closeTo(1.7, 1e-9),
      );
      // TARGET.
      expect(s.drag.currentTarget!.span.rowStart, 1);
      await _commit(tester, s);
      // TARGET.
      expect(s.viewport.rectOfItem("m")!.top, 50.0);
    });

    testWidgets("T6 a two-row item below a one-row header lands in the "
        "rows that show", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": const BoardSpan(rowStart: 25, colStart: 1, rowSpan: 2)},
        verticalScroll: 1000.0,
      );
      _lift(tester, s, const Offset(60.0, 275.0));
      _update(tester, s, const Offset(60.0, 35.0));
      // TARGET.
      expect(s.drag.currentTarget!.span.rowStart, 20);
      await _commit(tester, s);
      // TARGET.
      expect(s.viewport.rectOfItem("m")!.top, 0.0);
    });

    testWidgets("T7 a proxy mostly over the footer pins there", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenEnd: 1),
        items: {"m": const BoardSpan(rowStart: 2, colStart: 1)},
        cellBuilder: _plainCell,
      );
      // Setup sanity.
      expect(s.viewport.scrolledRegion.bottom, 250.0);
      _lift(tester, s, const Offset(60.0, 125.0));
      _update(tester, s, const Offset(60.0, 265.0));
      // TARGET.
      expect(s.drag.currentTarget!.span.rowStart, 29);
      await _commit(tester, s);
      // TARGET: the committed item is what shows there.
      expect(s.viewport.itemAt(const Offset(60.0, 275.0)), "m");
    });

    testWidgets("T8 a short item beside the footer lands in a row that "
        "shows", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenEnd: 1),
        items: {
          "m": const BoardSpan(
            rowStart: 2,
            colStart: 1,
            rowSpan: 0,
            rowSpanFraction: 0.5,
          ),
        },
      );
      _lift(tester, s, const Offset(60.0, 110.0));
      _update(tester, s, const Offset(60.0, 240.0));
      // TARGET.
      expect(s.drag.currentTarget!.span.rowStart, 4);
    });

    testWidgets("T9 an item taller than the footer dropped over it lands "
        "in the rows that show", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenEnd: 1),
        items: {"m": const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2)},
      );
      _lift(tester, s, const Offset(60.0, 125.0));
      _update(tester, s, const Offset(60.0, 295.0));
      // TARGET.
      expect(s.drag.currentTarget!.span.rowStart, 4);
      await _commit(tester, s);
      // TARGET.
      expect(s.viewport.rectOfItem("m")!.top, 200.0);
    });

    testWidgets("T10 control: a one-row item over the footer pins there", (
      tester,
    ) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenEnd: 1),
        items: {"m": const BoardSpan(rowStart: 2, colStart: 1)},
      );
      _lift(tester, s, const Offset(60.0, 125.0));
      _update(tester, s, const Offset(60.0, 295.0));
      expect(s.drag.currentTarget!.span.rowStart, 29);
    });

    testWidgets("T11 a reversed axis reads its band at the bottom", (
      tester,
    ) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": _m25},
        verticalScroll: 1000.0,
        verticalDetails: const ScrollableDetails(direction: AxisDirection.up),
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 0.0, 40.0, 50.0),
      );
      // Setup sanity.
      final corner = s.viewport.leadingCornerOf(
        const Rect.fromLTWH(40.0, 215.0, 40.0, 50.0),
      );
      expect(corner, const Offset(40.0, 265.0));
      expect(s.viewport.trackSpaceAt(corner)!.row, closeTo(0.7, 1e-9));
      _lift(tester, s, const Offset(60.0, 25.0));
      _update(tester, s, const Offset(60.0, 240.0));
      // TARGET.
      expect(s.drag.currentTarget!.span.rowStart, 21);
    });

    testWidgets("T12 the same rule on the columns", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(30, 40.0), frozenStart: 1),
        items: {"m": const BoardSpan(rowStart: 1, colStart: 25)},
        horizontalScroll: 800.0,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(200.0, 50.0, 40.0, 50.0),
      );
      _lift(tester, s, const Offset(220.0, 75.0));
      _update(tester, s, const Offset(48.0, 75.0));
      // TARGET.
      expect(s.drag.currentTarget!.span.colStart, 21);
    });

    testWidgets("T13 control: ordinary rounding beside the header", (
      tester,
    ) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": _m25},
        verticalScroll: 1010.0,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 240.0, 40.0, 50.0),
      );
      _lift(tester, s, const Offset(60.0, 265.0));
      _update(tester, s, const Offset(60.0, 77.0));
      expect(s.drag.currentTarget!.span.rowStart, 21);
    });

    testWidgets("T14 a tall item whose proxy is mostly below a short "
        "header lands below it", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(
          axis: ExplicitAxis(<double>[
            30.0,
            for (var i = 0; i < 29; i++) 100.0,
          ]),
          frozenStart: 1,
        ),
        items: {"m": const BoardSpan(rowStart: 3, colStart: 1)},
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 230.0, 40.0, 100.0),
      );
      _lift(tester, s, const Offset(60.0, 280.0));
      _update(tester, s, const Offset(60.0, 50.0));
      // TARGET.
      expect(s.drag.currentTarget!.span.rowStart, 1);
    });

    testWidgets("T15 a start that would move down while dragged up is "
        "refused", (tester) async {
      const stored = BoardSpan(
        rowStart: 19,
        rowFraction: 0.9,
        rowSpan: 1,
        rowSpanFraction: 0.2,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": stored},
        verticalScroll: 990.0,
      );
      expect(s.viewport.rectOfItem("m")!.top, closeTo(5.0, 1e-9));
      expect(s.viewport.rectOfItem("m")!.height, closeTo(60.0, 1e-9));
      // Setup sanity: the lift corner reads inside the viewport.
      expect(
        s.viewport.trackSpaceAt(const Offset(40.0, 5.0))!.row,
        closeTo(0.1, 1e-9),
      );
      _lift(tester, s, const Offset(60.0, 52.0));
      _update(tester, s, const Offset(60.0, 22.0));
      // TARGET.
      expect(s.drag.currentTarget!.span, stored);
    });

    testWidgets("T16 a band placement beyond the extended lift corner "
        "falls through", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {
          "m": const BoardSpan(rowStart: 20, rowFraction: 0.4, colStart: 1),
        },
        verticalScroll: 1050.0,
        snap: const BoardSnap.fraction(0.25),
      );
      expect(s.viewport.rectOfItem("m")!.top, closeTo(-30.0, 1e-9));
      _lift(tester, s, const Offset(60.0, 10.0));
      s.viewport.verticalPosition!.jumpTo(1000.0);
      await tester.pump();
      // Setup sanity.
      expect(
        s.viewport.trackSpaceAt(const Offset(40.0, 10.0))!.row,
        closeTo(0.2, 1e-9),
      );
      _update(tester, s, const Offset(60.0, 50.0));
      // TARGET.
      expect(
        s.drag.currentTarget!.span,
        const BoardSpan(rowStart: 20, rowFraction: 0.25, colStart: 1),
      );
    });

    testWidgets("T16b control: corners past the viewport's edge beside "
        "the header", (tester) async {
      const stored = BoardSpan(rowStart: 20, rowFraction: 0.4, colStart: 1);
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": stored},
        verticalScroll: 1050.0,
      );
      _lift(tester, s, const Offset(60.0, 10.0));
      _update(tester, s, const Offset(60.0, -20.0));
      expect(s.drag.currentTarget!.span, stored);
    });

    testWidgets("T17 a scrolled item's own dead zone keeps it", (tester) async {
      const stored = BoardSpan(
        rowStart: 20,
        rowFraction: 0.7,
        rowSpan: 0,
        rowSpanFraction: 0.5,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": stored},
        cellBuilder: _plainCell,
        verticalScroll: 1002.0,
        snap: const BoardSnap.fraction(0.35),
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 33.0, 40.0, 25.0),
      );
      _lift(tester, s, const Offset(60.0, 54.25));
      _update(tester, s, const Offset(60.0, 59.25));
      // TARGET.
      expect(s.drag.currentTarget!.span, stored);
    });

    testWidgets("T18 content scrolled toward the end under a still finger "
        "follows below the header", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {
          "m": const BoardSpan(rowStart: 20, rowFraction: 0.4, colStart: 1),
        },
        cellBuilder: _plainCell,
        verticalScroll: 1000.0,
      );
      _lift(tester, s, const Offset(60.0, 60.0));
      s.viewport.verticalPosition!.jumpTo(1200.0);
      await tester.pump();
      // TARGET.
      expect(s.drag.currentTarget!.span.rowStart, 25);
    });

    testWidgets("T19 a lattice clamp against the drag keeps the stored "
        "start", (tester) async {
      const stored = BoardSpan(
        rowStart: 5,
        rowFraction: 0.5,
        rowSpan: 0,
        rowSpanFraction: 0.5,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {"m": stored},
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 275.0, 40.0, 25.0),
      );
      _lift(tester, s, const Offset(60.0, 285.0));
      _update(tester, s, const Offset(60.0, 310.0));
      // TARGET.
      expect(s.drag.currentTarget!.span, stored);
    });

    testWidgets("T20 the GUARD tolerates the ulp a mapped lift corner "
        "carries", (tester) async {
      const stored = BoardSpan(
        rowStart: 0,
        rowFraction: 0.3762165975528743,
        rowSpan: 0,
        rowSpanFraction: 0.6237834024471257,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": stored},
        verticalScroll: 1000.0,
        snap: const BoardSnap.free(),
      );
      final rect = s.viewport.rectOfItem("m")!;
      const lift = Offset(60.0, 30.0);
      // Setup sanity: the lift corner reads one ulp past the stored start.
      final liftCorner = s.viewport
          .trackSpaceAt(
            s.viewport.leadingCornerOf(
              (lift - (lift - rect.topLeft)) & rect.size,
            ),
          )!
          .row;
      expect(liftCorner, 0.37621659755287434);
      expect(liftCorner, greaterThan(0.3762165975528743));
      _lift(tester, s, lift);
      _update(tester, s, const Offset(60.0, 35.0));
      // TARGET.
      expect(s.drag.currentTarget!.span, stored);
    });

    testWidgets("T21 a span its footer holds only within the tolerance at "
        "both ends moves", (tester) async {
      const stored = BoardSpan(
        rowStart: 27,
        rowFraction: 0.99999999994,
        rowSpan: 2,
        rowSpanFraction: 1.2e-10,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: _rows(frozenEnd: 2),
        items: {"m": stored},
      );
      // Setup sanity: the footer pins the span, which is longer than the
      // footer by more than the tolerance.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.trailing,
      );
      expect(bandWindowOf((start: 28, end: 30), 2.0 + 1.2e-10), isNull);
      final rect = s.viewport.rectOfItem("m")!;
      _lift(tester, s, rect.center);
      _update(tester, s, rect.center + const Offset(0.0, -60.0));
      // TARGET.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(
          rowStart: 3,
          rowSpan: 2,
          rowSpanFraction: 1.2e-10,
          colStart: 1,
        ),
      );
    });

    testWidgets("T22 a free-snap move clamped at the lattice's end on a board "
        "with no band ends on it", (tester) async {
      const stored = BoardSpan(
        rowStart: 2,
        rowFraction: 0.1,
        rowSpan: 2,
        rowSpanFraction: 0.1,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: _rows(),
        items: {"m": stored},
        snap: const BoardSnap.free(),
      );
      _lift(tester, s, const Offset(60.0, 150.0));
      s.viewport.verticalPosition!.jumpTo(1200.0);
      await tester.pump();
      _update(tester, s, const Offset(60.0, 250.0));
      final target = s.drag.currentTarget!.span;
      // TARGET.
      expect(target.startTrackOn(Axis.vertical), 27.9);
      expect(target.endTrackOn(Axis.vertical), 30.0);
    });

    testWidgets("T23 a pinned item whose corner leaves its header by a few "
        "pixels lands below it", (tester) async {
      const stored = BoardSpan(
        rowStart: 0,
        rowFraction: 0.9,
        rowSpan: 0,
        rowSpanFraction: 0.1,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": stored},
        verticalScroll: 1000.0,
        snap: const BoardSnap.fraction(0.4),
      );
      // Setup sanity: m is pinned in the header.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.leading,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 45.0, 40.0, 5.0),
      );
      _lift(tester, s, const Offset(60.0, 47.0));
      _update(tester, s, const Offset(60.0, 53.0));
      // TARGET.
      final target = s.drag.currentTarget?.span;
      expect(target?.startTrackOn(Axis.vertical), closeTo(21.2, 1e-9));
      expect(target?.endTrackOn(Axis.vertical), closeTo(21.3, 1e-9));
    });

    testWidgets("T24 a half-track item past the lattice's end under the "
        "track snap is floored to a whole track", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {
          "m": const BoardSpan(
            rowStart: 2,
            rowSpan: 0,
            rowSpanFraction: 0.5,
            colStart: 1,
          ),
        },
      );
      _lift(tester, s, const Offset(60.0, 110.0));
      _update(tester, s, const Offset(60.0, 290.0));
      // TARGET.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(
          rowStart: 5,
          rowSpan: 0,
          rowSpanFraction: 0.5,
          colStart: 1,
        ),
      );
    });

    testWidgets("T25 bands that fill the viewport place a span they cannot "
        "hold by the painted coordinate", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 6),
        items: {"m": const BoardSpan(rowStart: 15, rowSpan: 7, colStart: 1)},
        verticalScroll: 500.0,
      );
      // Setup sanity: the band leaves no scrolled region.
      final row = s.viewport.trackSampleAt(const Offset(60.0, 100.0))!.row;
      expect(row.visibleFrom, 16.0);
      expect(row.visibleTo, 16.0);
      _lift(tester, s, const Offset(60.0, 260.0));
      _update(tester, s, const Offset(60.0, 210.0));
      // TARGET.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 4, rowSpan: 7, colStart: 1),
      );
    });

    testWidgets("T26 a free-snap move clamped back onto its stored start "
        "keeps the stored fields", (tester) async {
      const stored = BoardSpan(
        rowStart: 28,
        rowFraction: 0.6,
        rowSpan: 1,
        rowSpanFraction: 0.4,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: _rows(),
        items: {"m": stored},
        verticalScroll: 1200.0,
        snap: const BoardSnap.free(),
      );
      _lift(tester, s, const Offset(60.0, 250.0));
      _update(tester, s, const Offset(60.0, 290.0));
      // TARGET: the stored fields, not a re-split of the clamped start.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("T27 a move past a viewport edge with no band is not held to "
        "what shows", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(),
        items: {"m": const BoardSpan(rowStart: 11, colStart: 1)},
        verticalScroll: 500.0,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 50.0, 40.0, 50.0),
      );
      _lift(tester, s, const Offset(60.0, 75.0));
      _update(tester, s, const Offset(60.0, -40.0));
      // TARGET.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 9, colStart: 1),
      );
    });

    testWidgets("T28 a proxy centred in the gap a short lattice leaves above "
        "its footer lands on the last scrolled row", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(5, 50.0), frozenEnd: 1),
        items: {"m": const BoardSpan(rowStart: 1, colStart: 1)},
      );
      // Setup sanity: the scrolled rows end at row 4, the footer's row.
      expect(
        s.viewport.trackSampleAt(const Offset(60.0, 100.0))!.row.visibleTo,
        4.0,
      );
      _lift(tester, s, const Offset(60.0, 75.0));
      _update(tester, s, const Offset(60.0, 215.0));
      // TARGET.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 3, colStart: 1),
      );
    });

    testWidgets("T29 under overscroll an item straddling the header's edge "
        "moved up never lands lower", (tester) async {
      const stored = BoardSpan(rowStart: 0, rowFraction: 0.3, colStart: 1);
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": stored},
        verticalDetails: const ScrollableDetails(
          direction: AxisDirection.down,
          physics: BouncingScrollPhysics(),
        ),
        snap: const BoardSnap.fraction(0.25),
      );
      // Held past the top: the spring back needs frames that advance
      // time, and the one pumped here advances none.
      s.viewport.verticalPosition!.jumpTo(-60.0);
      await tester.pump();
      // Setup sanity: the offset holds past the top, and the item paints
      // at its scrolled place below the header.
      expect(s.viewport.verticalPosition!.pixels, -60.0);
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 75.0, 40.0, 50.0),
      );
      _lift(tester, s, const Offset(60.0, 100.0));
      _update(tester, s, const Offset(60.0, 68.0));
      // Committed with one pump that advances no time, so the offset
      // still holds past the top.
      s.drag.endDrag(cancel: false);
      await tester.pump();
      // TARGET: moved up, the item paints no lower than it did.
      expect(s.viewport.rectOfItem("m")!.top, lessThanOrEqualTo(75.0 + 1e-9));
    });

    testWidgets("T30 a header item dragged down from a band shorter than "
        "the rows under it never lands higher", (tester) async {
      const stored = BoardSpan(
        rowStart: 0,
        rowFraction: 0.7,
        rowSpan: 0,
        rowSpanFraction: 0.25,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(
          axis: ExplicitAxis(<double>[
            30.0,
            for (var i = 0; i < 29; i++) 100.0,
          ]),
          frozenStart: 1,
        ),
        items: {"m": stored},
        verticalScroll: 10.0,
      );
      // Setup sanity: the item is pinned in the 30 px header, painting at
      // 21 px, where the scrolled row under it reads past row 1's start.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.leading,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 21.0, 40.0, 7.5),
      );
      expect(
        s.viewport.trackSampleAt(const Offset(60.0, 21.0))!.row.scrolled,
        closeTo(1.01, 1e-9),
      );
      _lift(tester, s, const Offset(60.0, 22.0));
      _update(tester, s, const Offset(60.0, 34.0));
      await _commit(tester, s);
      // TARGET: moved down, the item paints no higher than it did.
      expect(
        s.viewport.rectOfItem("m")!.top,
        greaterThanOrEqualTo(21.0 - 1e-9),
      );
    });

    testWidgets("T31 a span longer than a one-row header by less than the "
        "tolerance lands in it", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {
          "m": const BoardSpan(
            rowStart: 25,
            rowSpan: 1,
            rowSpanFraction: 5e-11,
            colStart: 1,
          ),
        },
        verticalScroll: 1000.0,
      );
      _lift(tester, s, const Offset(60.0, 275.0));
      _update(tester, s, const Offset(60.0, 45.0));
      // TARGET: the band's window admits the span within the tolerance, so
      // a proxy centred over the header lands in it.
      expect(s.drag.currentTarget?.span.rowStart, 0);
    });

    testWidgets("T32 a scrolled window's first start, an ulp off a track "
        "edge, is that edge", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 3),
        items: {"m": const BoardSpan(rowStart: 8, rowSpan: 4, colStart: 1)},
        verticalScroll: 390.0,
        snap: const BoardSnap.fraction(0.28),
      );
      _lift(tester, s, const Offset(60.0, 180.0));
      _update(tester, s, const Offset(60.0, 110.0));
      // TARGET: the first start that shows below the header, row 7 exactly,
      // not a fraction an ulp above it.
      expect(s.drag.currentTarget?.span.startTrackOn(Axis.vertical), 7.0);
    });

    testWidgets("T33 a scrolled window's last start, an ulp off a track "
        "edge, is that edge", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenEnd: 2),
        items: {"m": const BoardSpan(rowStart: 4, rowSpan: 4, colStart: 1)},
        verticalScroll: 160.0,
        snap: const BoardSnap.fraction(0.28),
      );
      _lift(tester, s, const Offset(60.0, 100.0));
      _update(tester, s, const Offset(60.0, 270.0));
      // TARGET: the last start that shows above the footer, row 7 exactly.
      expect(s.drag.currentTarget?.span.startTrackOn(Axis.vertical), 7.0);
    });

    testWidgets("T34 a scrolled window of one start places the item there", (
      tester,
    ) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(
          axis: ExplicitAxis(<double>[for (var i = 0; i < 19; i++) 50.0, 37.5]),
          frozenStart: 5,
          frozenEnd: 1,
        ),
        items: {
          "m": const BoardSpan(
            rowStart: 1,
            rowSpan: 0,
            rowSpanFraction: 0.25,
            colStart: 1,
          ),
        },
        verticalScroll: 25.0,
        snap: const BoardSnap.fraction(0.25),
      );
      // Setup sanity: a quarter-track span shows between the bands only at
      // 5.5, the window's one start.
      final row = s.viewport.trackSampleAt(const Offset(60.0, 251.0))!.row;
      expect((row.visibleFrom, row.visibleTo), (5.5, 5.75));
      _lift(tester, s, const Offset(60.0, 55.0));
      _update(tester, s, const Offset(60.0, 250.0));
      // TARGET: the one start, not the whole lattice's.
      expect(s.drag.currentTarget?.span.startTrackOn(Axis.vertical), 5.5);
    });
  });

  group("the drop fit over a band", () {
    Future<_Setup> fitSetup(
      WidgetTester tester, {
      required Map<String, BoardSpan> others,
      required BoardDropFit dropFit,
    }) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": _m25, ...others},
        verticalScroll: 1000.0,
        dropFit: dropFit,
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(60.0, 275.0));
      s.asked.clear();
      return s;
    }

    testWidgets("F1 a refused span in the header is nudged within it", (
      tester,
    ) async {
      final s = await fitSetup(
        tester,
        others: {
          "a": const BoardSpan(rowStart: 0, colStart: 0),
          "b": const BoardSpan(rowStart: 0, colStart: 1),
          "c": const BoardSpan(rowStart: 0, colStart: 2),
        },
        dropFit: const BoardDropFit(minFreeFraction: 0.0),
      );
      _update(tester, s, const Offset(60.0, 35.0));
      // Setup sanity.
      expect(s.asked.first, const BoardSpan(rowStart: 0, colStart: 1));
      // TARGET.
      expect(s.drag.currentTarget, isNull);
    });

    testWidgets("F2 a refused scrolled span is nudged only to rows that "
        "show", (tester) async {
      final s = await fitSetup(
        tester,
        others: {
          "a": const BoardSpan(rowStart: 21, colStart: 0),
          "b": const BoardSpan(rowStart: 21, colStart: 1),
          "c": const BoardSpan(rowStart: 21, colStart: 2),
        },
        dropFit: const BoardDropFit(minFreeFraction: 0.0),
      );
      _update(tester, s, const Offset(60.0, 75.0));
      // Setup sanity.
      expect(s.asked.first, const BoardSpan(rowStart: 21, colStart: 1));
      // TARGET.
      expect(s.drag.currentTarget!.span.rowStart, 22);
    });

    testWidgets("F3 the gate measures only the tracks a candidate can "
        "use", (tester) async {
      final s = await fitSetup(
        tester,
        others: {
          "a": const BoardSpan(rowStart: 21, colStart: 0),
          "b": const BoardSpan(rowStart: 21, colStart: 1),
          "c": const BoardSpan(rowStart: 21, colStart: 2),
          "d": const BoardSpan(rowStart: 20, colStart: 0),
          "e": const BoardSpan(rowStart: 20, colStart: 1),
          "f": const BoardSpan(rowStart: 20, colStart: 2),
        },
        dropFit: const BoardDropFit(minFreeFraction: 0.4),
      );
      _update(tester, s, const Offset(60.0, 75.0));
      // TARGET.
      expect(s.drag.currentTarget?.span.rowStart, 22);
    });

    testWidgets("F4 control: the region covers candidates the window "
        "clamp carries past the radius", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 3),
        items: {
          "m": const BoardSpan(rowStart: 20, colStart: 1),
          "a": const BoardSpan(rowStart: 20, colStart: 1),
          "b": const BoardSpan(rowStart: 23, colStart: 1),
        },
        verticalScroll: 1000.0,
        dropFit: const BoardDropFit(minFreeFraction: 0.0, colRadius: 0.0),
        canDropAt: (controller, key, span) {
          return span.rowStart >= 23;
        },
      );
      expect(s.viewport.rectOfItem("m")!.top, 0.0);
      _lift(tester, s, const Offset(60.0, 25.0));
      expect(s.drag.currentTarget, isNull);
    });

    testWidgets("F9 a scroll that moves the window under a parked pointer "
        "re-runs the nudge", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {
          "m": const BoardSpan(rowStart: 20, rowFraction: 0.4, colStart: 1),
          "a": const BoardSpan(
            rowStart: 21,
            rowSpan: 0,
            rowSpanFraction: 0.4,
            colStart: 1,
          ),
        },
        verticalScroll: 995.0,
        dropFit: const BoardDropFit(
          minFreeFraction: 0.0,
          rowRadius: 1.0,
          colRadius: 0.0,
        ),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(60.0, 60.0));
      s.viewport.verticalPosition!.jumpTo(1005.0);
      await tester.pump();
      // Setup sanity: row 21 is the first that shows, so a span starting
      // at 20 lies under the header.
      expect(
        s.viewport.trackSampleAt(const Offset(60.0, 100.0))!.row.visibleFrom,
        closeTo(21.1, 1e-9),
      );
      // TARGET.
      final target = s.drag.currentTarget?.span;
      expect(target?.startTrackOn(Axis.vertical), closeTo(21.4, 1e-9));
      expect(target?.endTrackOn(Axis.vertical), closeTo(22.4, 1e-9));
    });

    testWidgets("F10 a radius the scan does not step measures today's "
        "widened box beside a band", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {
          "b": const BoardSpan(rowStart: 0, colStart: 1),
          "m": const BoardSpan(rowStart: 0, colStart: 1),
        },
        verticalScroll: 1000.0,
        dropFit: const BoardDropFit(
          minFreeFraction: 0.75,
          rowRadius: 0.5,
          colRadius: 1.0,
        ),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(60.0, 25.0));
      // Setup sanity: the lift's own placement is the first span asked.
      expect(s.asked.first, const BoardSpan(rowStart: 0, colStart: 1));
      // TARGET.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 0, colStart: 0),
      );
    });

    testWidgets("F21 the region's far end stops at the last start that shows "
        "beside the footer", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenEnd: 1),
        items: {
          "m": const BoardSpan(rowStart: 1, colStart: 1),
          "a0": const BoardSpan(rowStart: 4, colStart: 0),
          "a1": const BoardSpan(rowStart: 4, colStart: 1),
          "a2": const BoardSpan(rowStart: 4, colStart: 2),
          "b0": const BoardSpan(rowStart: 5, colStart: 0),
          "b1": const BoardSpan(rowStart: 5, colStart: 1),
          "b2": const BoardSpan(rowStart: 5, colStart: 2),
        },
        dropFit: const BoardDropFit(minFreeFraction: 0.4),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(60.0, 75.0));
      _update(tester, s, const Offset(60.0, 225.0));
      // Setup sanity: the placement at row 4 is asked, and refused.
      expect(s.asked, contains(const BoardSpan(rowStart: 4, colStart: 1)));
      // TARGET: the region ends at the last start that shows, so the rows
      // hidden under the footer do not crowd the gate, and the nudge lands
      // on row 3.
      expect(s.drag.currentTarget?.span.rowStart, 3);
    });

    testWidgets("F23 a refused box past the lattice's end beside a footer "
        "lands on the last row that shows above it", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(10, 30.0), frozenEnd: 2),
        items: {
          "m": const BoardSpan(rowStart: 6, colStart: 1),
          "o": const BoardSpan(rowStart: 6, colStart: 1),
        },
        dropFit: const BoardDropFit(minFreeFraction: 0.0),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(60.0, 195.0));
      s.controller.rows = BoardAxisConfig(
        axis: UniformAxis(5, 30.0),
        frozenEnd: 2,
      );
      await tester.pump();
      // TARGET: the box lies past the five rows; the last row that shows
      // above the two-row footer is 2, so it lands there and scrolls,
      // rather than pinning into the footer under no proxy's centre.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 2, colStart: 1),
      );
    });

    testWidgets("F24 a refused lift of an item past the columns' end beside a "
        "column band lands on the last column that shows", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(20, 40.0), frozenEnd: 1),
        items: {
          "m": const BoardSpan(rowStart: 2, colStart: 22),
          "o": const BoardSpan(rowStart: 2, colStart: 22),
        },
        dropFit: const BoardDropFit(minFreeFraction: 0.0),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(100.0, 125.0));
      // TARGET: six scrolled columns show beside the one-column band, so the
      // box lands on column 5 rather than in the band.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 2, colStart: 5),
      );
    });
  });

  group("the lift rule over a band", () {
    testWidgets("K1 a scrolled item whose corner crosses into the header "
        "keeps its dead zone", (tester) async {
      const stored = BoardSpan(rowStart: 21, rowFraction: 0.1, colStart: 1);
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": stored},
        verticalScroll: 1002.0,
        snap: const BoardSnap.fraction(0.25),
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 53.0, 40.0, 50.0),
      );
      // Setup sanity.
      expect(
        s.viewport.trackSpaceAt(const Offset(40.0, 49.0))!.row,
        closeTo(0.98, 1e-9),
      );
      _lift(tester, s, const Offset(60.0, 78.0));
      _update(tester, s, const Offset(60.0, 74.0));
      // TARGET.
      expect(s.drag.currentTarget!.span, stored);
    });

    BoardAxisConfig lanedRows() {
      return BoardAxisConfig(
        axis: UniformAxis(30, 50.0),
        frozenStart: 1,
        laneExtent: 50.0,
      );
    }

    testWidgets("K2 control: a laned item pressed through the header "
        "keeps its row", (tester) async {
      final s = await _setup(
        tester,
        rows: lanedRows(),
        items: {"m": const BoardSpan(rowStart: 20, colStart: 1)},
        verticalScroll: 1020.0,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, -20.0, 40.0, 50.0),
      );
      // Setup sanity.
      expect(
        s.viewport.trackSpaceAt(const Offset(60.0, 20.0))!.row,
        closeTo(0.4, 1e-9),
      );
      _lift(tester, s, const Offset(60.0, 20.0));
      expect(s.drag.currentTarget!.span.rowStart, 20);
    });

    testWidgets("K3 that laned item follows by rows in its own lattice", (
      tester,
    ) async {
      final s = await _setup(
        tester,
        rows: lanedRows(),
        items: {"m": const BoardSpan(rowStart: 20, colStart: 1)},
        verticalScroll: 1020.0,
      );
      _lift(tester, s, const Offset(60.0, 20.0));
      _update(tester, s, const Offset(60.0, 60.0));
      // TARGET.
      expect(s.drag.currentTarget!.span.rowStart, 21);
    });

    testWidgets("K4 a refused motionless lift in the header is nudged "
        "within it", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {
          "a": const BoardSpan(rowStart: 0, colStart: 0),
          "b": const BoardSpan(rowStart: 0, colStart: 1),
          "c": const BoardSpan(rowStart: 0, colStart: 2),
          "m": const BoardSpan(rowStart: 0, colStart: 1),
        },
        verticalScroll: 1000.0,
        dropFit: const BoardDropFit(minFreeFraction: 0.0),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(60.0, 25.0));
      // TARGET.
      expect(s.drag.currentTarget, isNull);
    });

    testWidgets("K5 control: a 1 px move across the header's edge keeps "
        "the item", (tester) async {
      const stored = BoardSpan(rowStart: 20, colStart: 1);
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": stored},
        verticalScroll: 975.0,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 25.0, 40.0, 50.0),
      );
      _lift(tester, s, const Offset(60.0, 60.0));
      _update(tester, s, const Offset(60.0, 59.0));
      expect(s.drag.currentTarget!.span, stored);
    });

    testWidgets("K6 control: a 6 px move out of the header keeps the "
        "item", (tester) async {
      const stored = BoardSpan(rowStart: 20, rowFraction: 0.4, colStart: 1);
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": stored},
        verticalScroll: 1000.0,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 20.0, 40.0, 50.0),
      );
      _lift(tester, s, const Offset(60.0, 45.0));
      _update(tester, s, const Offset(60.0, 51.0));
      expect(s.drag.currentTarget!.span, stored);
    });

    testWidgets("K7 autoscroll under a still finger releases a corner "
        "held in the header", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {
          "m": const BoardSpan(rowStart: 20, rowFraction: 0.4, colStart: 1),
        },
        cellBuilder: _plainCell,
        verticalScroll: 1000.0,
        autoScrollEdgeZone: 48.0,
      );
      _lift(tester, s, const Offset(60.0, 60.0));
      var frames = 0;
      while (s.viewport.verticalPosition!.pixels > 975.0 && frames < 600) {
        await tester.pump(const Duration(milliseconds: 16));
        frames += 1;
      }
      // Setup sanity: the autoscroll reached the offset.
      expect(s.viewport.verticalPosition!.pixels, lessThanOrEqualTo(975.0));
      // TARGET.
      expect(s.drag.currentTarget!.span.rowStart, 0);
      s.drag.endDrag(cancel: true);
      await tester.pump();
    });

    testWidgets("K8 control: a laned chip lands on the row under the "
        "finger", (tester) async {
      final s = await _setup(
        tester,
        rows: lanedRows(),
        items: {
          "m": const BoardSpan(
            rowStart: 25,
            rowSpan: 0,
            rowSpanFraction: 0.5,
            colStart: 1,
          ),
        },
        verticalScroll: 1030.0,
      );
      expect(s.controller.isLanedId(s.controller.idOfKey("m")), isTrue);
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 220.0, 40.0, 50.0),
      );
      _lift(tester, s, const Offset(60.0, 225.0));
      _update(tester, s, const Offset(60.0, 60.0));
      expect(s.drag.currentTarget!.span.rowStart, 21);
    });

    testWidgets("K9 a band removed mid-hold keeps the item", (tester) async {
      const stored = BoardSpan(rowStart: 20, rowFraction: 0.4, colStart: 1);
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": stored},
        verticalScroll: 1000.0,
      );
      _lift(tester, s, const Offset(60.0, 45.0));
      s.controller.rows = BoardAxisConfig(
        axis: s.controller.rows.axis,
        frozenStart: 0,
      );
      await tester.pump();
      // TARGET.
      expect(s.drag.currentTarget!.span, stored);
    });

    testWidgets("K10 a band added mid-hold that pins the item keeps it", (
      tester,
    ) async {
      const stored = BoardSpan(
        rowStart: 0,
        rowFraction: 0.1,
        rowSpan: 0,
        rowSpanFraction: 0.5,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0)),
        items: {"m": stored},
        verticalScroll: 25.0,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, -20.0, 40.0, 25.0),
      );
      _lift(tester, s, const Offset(60.0, 0.75));
      s.controller.rows = BoardAxisConfig(
        axis: s.controller.rows.axis,
        frozenStart: 1,
      );
      await tester.pump();
      // Setup sanity: the new band pins the item.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.leading,
      );
      // TARGET.
      expect(s.drag.currentTarget!.span, stored);
    });

    testWidgets("K11 control: a laned item whose pointer moves over the "
        "header lands in it", (tester) async {
      final s = await _setup(
        tester,
        rows: lanedRows(),
        items: {"m": const BoardSpan(rowStart: 21, colStart: 1)},
        verticalScroll: 1000.0,
      );
      // Setup sanity: m is laned and shows below the header.
      expect(s.controller.isLanedId(s.controller.idOfKey("m")), isTrue);
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 50.0, 40.0, 50.0),
      );
      _lift(tester, s, const Offset(60.0, 75.0));
      _update(tester, s, const Offset(60.0, 25.0));
      // TARGET.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 0, colStart: 1),
      );
    });

    testWidgets("K12 a band widened mid-hold after a scroll keeps the "
        "lift's scrolled coordinate", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {
          "m": const BoardSpan(rowStart: 20, rowFraction: 0.4, colStart: 1),
        },
        cellBuilder: _plainCell,
        verticalScroll: 1000.0,
      );
      _lift(tester, s, const Offset(60.0, 60.0));
      s.viewport.verticalPosition!.jumpTo(1030.0);
      await tester.pump();
      s.controller.rows = BoardAxisConfig(
        axis: s.controller.rows.axis,
        frozenStart: 2,
      );
      await tester.pump();
      // TARGET.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 22, colStart: 1),
      );
    });

    testWidgets("K13 a refused motionless lift in the footer is nudged "
        "within it", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenEnd: 1),
        items: {
          "a": const BoardSpan(rowStart: 29, colStart: 0),
          "b": const BoardSpan(rowStart: 29, colStart: 1),
          "c": const BoardSpan(rowStart: 29, colStart: 2),
          "m": const BoardSpan(rowStart: 29, colStart: 1),
        },
        dropFit: const BoardDropFit(minFreeFraction: 0.0),
        canDropAt: _noOverlap,
      );
      // Setup sanity: m is pinned in the footer.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.trailing,
      );
      _lift(tester, s, const Offset(60.0, 275.0));
      // TARGET.
      expect(s.drag.currentTarget, isNull);
    });

    testWidgets("K14 a footer removed mid-hold over a short lattice keeps "
        "a moved item", (tester) async {
      const stored = BoardSpan(
        rowStart: 4,
        rowSpan: 0,
        rowSpanFraction: 0.5,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(5, 50.0), frozenEnd: 1),
        items: {"m": stored},
        snap: const BoardSnap.fraction(0.25),
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 250.0, 40.0, 25.0),
      );
      _lift(tester, s, const Offset(60.0, 262.5));
      s.controller.rows = BoardAxisConfig(axis: s.controller.rows.axis);
      await tester.pump();
      // Setup sanity: the item now scrolls, and its lift corner reads
      // past the lattice's end.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.none,
      );
      expect(
        s.viewport.trackSampleAt(const Offset(60.0, 250.0))!.row.painted,
        5.0,
      );
      // TARGET.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("K15 columns added mid-hold beside a short lattice's "
        "footer keep a moved item", (tester) async {
      const stored = BoardSpan(
        rowStart: 2,
        colStart: 4,
        colSpan: 0,
        colSpanFraction: 0.5,
      );
      final s = await _setup(
        tester,
        rows: _rows(),
        columns: BoardAxisConfig(axis: UniformAxis(5, 40.0), frozenEnd: 1),
        items: {"m": stored},
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(240.0, 100.0, 20.0, 50.0),
      );
      _lift(tester, s, const Offset(250.0, 125.0));
      s.controller.columns = BoardAxisConfig(
        axis: UniformAxis(7, 40.0),
        frozenEnd: 1,
      );
      await tester.pump();
      // Setup sanity: the item now scrolls, and its lift corner's scrolled
      // coordinate lies past the lift lattice's last column.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.horizontal),
        BoardPin.none,
      );
      expect(
        s.viewport.trackSampleAt(const Offset(240.0, 125.0))!.col.scrolled,
        6.0,
      );
      // TARGET.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("K16 a footer resized under a held item to the same start "
        "keeps it", (tester) async {
      const stored = BoardSpan(
        rowStart: 4,
        rowSpan: 0,
        rowSpanFraction: 0.5,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(5, 50.0), frozenEnd: 1),
        items: {"m": stored},
        snap: const BoardSnap.fraction(0.25),
      );
      _lift(tester, s, const Offset(60.0, 262.5));
      s.controller.rows = BoardAxisConfig(
        axis: UniformAxis(6, 50.0),
        frozenEnd: 2,
      );
      await tester.pump();
      // Setup sanity: the footer still starts at row 4, so the item stays
      // pinned in it, while the track count changed.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.trailing,
      );
      // TARGET: the lift is sampled again under the new count, so the
      // still finger moves nothing.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("K17 a band added on one axis samples that axis again and "
        "not the other", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0)),
        items: {"m": const BoardSpan(rowStart: 3, colStart: 2)},
        snap: const BoardSnap.fraction(0.25),
      );
      _lift(tester, s, const Offset(100.0, 175.0));
      s.controller.rows = BoardAxisConfig(
        axis: s.controller.rows.axis,
        frozenStart: 1,
      );
      s.controller.columns = BoardAxisConfig(axis: UniformAxis(7, 30.0));
      await tester.pump();
      // TARGET: the rows, whose band changed, are sampled again and keep
      // their start; the columns, zoomed under the same count and bands,
      // are not, so the zoom reads as a displacement there.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 3, colStart: 2, colFraction: 0.75),
      );
    });
  });

  group("resizes over a band", () {
    testWidgets("R1 a leading edge dragged into the header stops at the "
        "first row that shows", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": const BoardSpan(rowStart: 24, colStart: 1, rowSpan: 2)},
        verticalScroll: 1000.0,
        resize: true,
      );
      _liftEdge(tester, s, const Offset(60.0, 204.0), BoardResizeEdges.leading);
      _update(tester, s, const Offset(60.0, 35.0));
      // TARGET.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 21, colStart: 1, rowSpan: 5),
      );
    });

    testWidgets("R2 a trailing edge dragged into the footer stops at the "
        "last row that shows", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenEnd: 1),
        items: {"m": const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2)},
        resize: true,
      );
      _liftEdge(
        tester,
        s,
        const Offset(60.0, 196.0),
        BoardResizeEdges.trailing,
      );
      _update(tester, s, const Offset(60.0, 270.0));
      // TARGET.
      expect(s.drag.currentTarget?.span.rowSpan, 3);
    });

    testWidgets("R3 a leading edge beside the footer stays on a row that "
        "shows", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenEnd: 1),
        items: {"m": const BoardSpan(rowStart: 3, colStart: 1, rowSpan: 5)},
        resize: true,
      );
      _liftEdge(tester, s, const Offset(60.0, 154.0), BoardResizeEdges.leading);
      _update(tester, s, const Offset(60.0, 270.0));
      // TARGET.
      expect(s.drag.currentTarget?.span.rowStart, 4);
    });

    testWidgets("R4 control: a pinned item grown inside its band stays "
        "pinned", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 2),
        items: {"m": const BoardSpan(rowStart: 0, colStart: 1)},
        verticalScroll: 1000.0,
        resize: true,
      );
      _liftEdge(tester, s, const Offset(60.0, 48.0), BoardResizeEdges.trailing);
      _update(tester, s, const Offset(60.0, 95.0));
      // TARGET.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 0, colStart: 1, rowSpan: 2),
      );
    });

    testWidgets("R5 a free-snap edge pulled just out of its band reaches "
        "the first quarter track that shows", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 2),
        items: {"m": const BoardSpan(rowStart: 0, colStart: 1)},
        verticalScroll: 1000.0,
        snap: const BoardSnap.free(),
        resize: true,
      );
      _liftEdge(tester, s, const Offset(60.0, 48.0), BoardResizeEdges.trailing);
      _update(tester, s, const Offset(60.0, 99.0));
      // TARGET.
      expect(s.drag.currentTarget?.span.endTrackOn(Axis.vertical), 22.25);
      await _commit(tester, s);
      // TARGET: the committed item's end shows below the band.
      expect(s.viewport.rectOfItem("m")!.bottom, 112.5);
    });

    testWidgets("R6 control: a pinned item's edge dragged out of its band "
        "is measured in the band", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": const BoardSpan(rowStart: 0, colStart: 1)},
        verticalScroll: 1000.0,
        resize: true,
      );
      _liftEdge(tester, s, const Offset(60.0, 48.0), BoardResizeEdges.trailing);
      _update(tester, s, const Offset(60.0, 160.0));
      // TARGET.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 0, colStart: 1, rowSpan: 23),
      );
    });

    testWidgets("R7 a scrolled item pressed through a transparent header "
        "is measured in its own lattice", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": const BoardSpan(rowStart: 19, colStart: 1, rowSpan: 2)},
        verticalScroll: 1020.0,
        resize: true,
      );
      // Setup sanity.
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, -70.0, 40.0, 100.0),
      );
      expect(
        s.viewport.trackSpaceAt(const Offset(60.0, 25.0))!.row,
        closeTo(0.5, 1e-9),
      );
      _liftEdge(tester, s, const Offset(60.0, 25.0), BoardResizeEdges.trailing);
      _update(tester, s, const Offset(60.0, 80.0));
      // TARGET.
      expect(s.drag.currentTarget?.span.rowSpan, 3);
    });

    testWidgets("R8 control: a straddler shrunk into the header pins "
        "there", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": const BoardSpan(rowStart: 0, colStart: 1, rowSpan: 2)},
        resize: true,
      );
      // Setup sanity.
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 0.0, 40.0, 100.0),
      );
      _liftEdge(tester, s, const Offset(60.0, 95.0), BoardResizeEdges.trailing);
      _update(tester, s, const Offset(60.0, 45.0));
      // TARGET.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 0, colStart: 1),
      );
    });

    testWidgets("R8b control: a scrolled straddler shrunk into the header "
        "pins there", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": const BoardSpan(rowStart: 0, colStart: 1, rowSpan: 22)},
        verticalScroll: 1000.0,
        resize: true,
      );
      // Setup sanity.
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, -1000.0, 40.0, 1100.0),
      );
      _liftEdge(tester, s, const Offset(60.0, 95.0), BoardResizeEdges.trailing);
      _update(tester, s, const Offset(60.0, 45.0));
      // TARGET.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 0, colStart: 1),
      );
    });

    testWidgets("R9 control: a straddler shrunk into the footer pins "
        "there", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenEnd: 1),
        items: {"m": const BoardSpan(rowStart: 28, colStart: 1, rowSpan: 2)},
        verticalScroll: 1200.0,
        resize: true,
      );
      // Setup sanity.
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 200.0, 40.0, 100.0),
      );
      _liftEdge(tester, s, const Offset(60.0, 205.0), BoardResizeEdges.leading);
      _update(tester, s, const Offset(60.0, 255.0));
      // TARGET.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 29, colStart: 1),
      );
    });

    testWidgets("R10 control: a pinned item's handle jittered across its "
        "band's edge stays", (tester) async {
      const stored = BoardSpan(rowStart: 0, colStart: 1);
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": stored},
        resize: true,
      );
      _liftEdge(tester, s, const Offset(60.0, 48.0), BoardResizeEdges.trailing);
      _update(tester, s, const Offset(60.0, 51.0));
      // TARGET.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("R11 an edge the shows bound would push against the drag "
        "keeps the stored span", (tester) async {
      const stored = BoardSpan(
        rowStart: 19,
        rowSpan: 1,
        rowSpanFraction: 0.5,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": stored},
        verticalScroll: 960.0,
        resize: true,
      );
      // Setup sanity.
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, -10.0, 40.0, 75.0),
      );
      _liftEdge(tester, s, const Offset(60.0, 62.0), BoardResizeEdges.trailing);
      _update(tester, s, const Offset(60.0, 32.0));
      // TARGET.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("R12 a free-snap edge on a board with no band moves by the "
        "pointer's displacement", (tester) async {
      const stored = BoardSpan(
        rowStart: 1,
        rowSpan: 2,
        rowSpanFraction: 0.05,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: _rows(),
        items: {"m": stored},
        snap: const BoardSnap.free(),
        resize: true,
      );
      _liftEdge(
        tester,
        s,
        const Offset(60.0, 150.0),
        BoardResizeEdges.trailing,
      );
      _update(tester, s, const Offset(60.0, 157.0));
      // TARGET: the stored end plus the 0.14 tracks the pointer moved.
      expect(s.drag.currentTarget!.span.endTrackOn(Axis.vertical), 3.19);
    });

    testWidgets("R13 control: an edge beside bands that fill the viewport "
        "is not held to a region that shows", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 6),
        items: {"m": const BoardSpan(rowStart: 5, rowSpan: 3, colStart: 1)},
        snap: const BoardSnap.free(),
        resize: true,
      );
      // Setup sanity: the band leaves no scrolled region, and m scrolls.
      final row = s.viewport.trackSampleAt(const Offset(60.0, 100.0))!.row;
      expect(row.visibleFrom, 6.0);
      expect(row.visibleTo, 6.0);
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.none,
      );
      _liftEdge(
        tester,
        s,
        const Offset(60.0, 290.0),
        BoardResizeEdges.trailing,
      );
      _update(tester, s, const Offset(60.0, 195.0));
      // TARGET.
      expect(s.drag.currentTarget?.span.endTrackOn(Axis.vertical), 6.1);
    });

    testWidgets("R14 a band added mid-hold that pins a resized item keeps "
        "its span", (tester) async {
      const stored = BoardSpan(
        rowStart: 0,
        rowFraction: 0.1,
        rowSpan: 0,
        rowSpanFraction: 0.5,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0)),
        items: {"m": stored},
        verticalScroll: 25.0,
        snap: const BoardSnap.free(),
        resize: true,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, -20.0, 40.0, 25.0),
      );
      _liftEdge(tester, s, const Offset(60.0, 3.0), BoardResizeEdges.trailing);
      s.controller.rows = BoardAxisConfig(
        axis: s.controller.rows.axis,
        frozenStart: 1,
      );
      await tester.pump();
      // Setup sanity: the new band pins the item.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.leading,
      );
      // TARGET.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("R15 a leading edge of a pinned item whose end is its band's "
        "end resizes in the band", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 2),
        items: {"m": const BoardSpan(rowStart: 0, rowSpan: 2, colStart: 1)},
        verticalScroll: 1000.0,
        snap: const BoardSnap.fraction(0.25),
        resize: true,
      );
      // Setup sanity: m fills the two-row header.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.leading,
      );
      _liftEdge(tester, s, const Offset(60.0, 2.0), BoardResizeEdges.leading);
      _update(tester, s, const Offset(60.0, 27.0));
      // TARGET.
      final target = s.drag.currentTarget?.span;
      expect(target?.startTrackOn(Axis.vertical), 0.5);
      expect(target?.endTrackOn(Axis.vertical), 2.0);
    });

    testWidgets("R16 a pinned edge floored back onto its stored value keeps "
        "the stored fields", (tester) async {
      const stored = BoardSpan(
        rowStart: 0,
        rowFraction: 0.3,
        rowSpan: 0,
        rowSpanFraction: 0.25,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": stored},
        verticalScroll: 1000.0,
        snap: const BoardSnap.free(),
        resize: true,
      );
      // Setup sanity: m is pinned in the header.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.leading,
      );
      _liftEdge(tester, s, const Offset(60.0, 16.0), BoardResizeEdges.leading);
      _update(tester, s, const Offset(60.0, 36.0));
      // TARGET: the stored fields, not a re-split of the floored edge.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("R17 a footer item's trailing edge dragged into the gap "
        "above a short lattice's footer keeps its span", (tester) async {
      const stored = BoardSpan(
        rowStart: 4,
        rowSpan: 0,
        rowSpanFraction: 0.25,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(5, 50.0), frozenEnd: 1),
        items: {"m": stored},
        snap: const BoardSnap.fraction(0.25),
        resize: true,
      );
      // Setup sanity: m is pinned in the footer, which paints at the
      // viewport's foot with the gap above it.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.trailing,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 250.0, 40.0, 12.5),
      );
      _liftEdge(
        tester,
        s,
        const Offset(60.0, 260.5),
        BoardResizeEdges.trailing,
      );
      _update(tester, s, const Offset(60.0, 248.5));
      // TARGET.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("R18 a footer item's leading edge dragged into the gap "
        "above a short lattice's footer moves up", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(5, 50.0), frozenEnd: 1),
        items: {
          "m": const BoardSpan(
            rowStart: 4,
            rowSpan: 0,
            rowSpanFraction: 0.5,
            colStart: 1,
          ),
        },
        snap: const BoardSnap.free(),
        resize: true,
      );
      // Setup sanity: m is pinned in the footer.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.trailing,
      );
      _liftEdge(tester, s, const Offset(60.0, 252.0), BoardResizeEdges.leading);
      _update(tester, s, const Offset(60.0, 248.0));
      // TARGET.
      final target = s.drag.currentTarget?.span;
      expect(target?.startTrackOn(Axis.vertical), 3.75);
      expect(target?.endTrackOn(Axis.vertical), 4.5);
    });

    testWidgets("R19 a footer item's leading edge dragged to the footer's "
        "top row of a short lattice moves up", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(5, 50.0), frozenEnd: 1),
        items: {
          "m": const BoardSpan(
            rowStart: 4,
            rowFraction: 0.2,
            rowSpan: 0,
            rowSpanFraction: 0.5,
            colStart: 1,
          ),
        },
        snap: const BoardSnap.free(),
        resize: true,
      );
      // Setup sanity: m is pinned in the footer, and the update stays
      // over it.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.trailing,
      );
      expect(s.viewport.trackSampleAt(const Offset(60.0, 250.0))!.row.band, (
        start: 4,
        end: 5,
      ));
      _liftEdge(tester, s, const Offset(60.0, 262.0), BoardResizeEdges.leading);
      _update(tester, s, const Offset(60.0, 250.0));
      // TARGET.
      final target = s.drag.currentTarget?.span;
      expect(target?.startTrackOn(Axis.vertical), 3.75);
      expect(target?.endTrackOn(Axis.vertical), closeTo(4.7, 1e-9));
    });

    testWidgets("R21 a footer added mid-hold over a short lattice's gap "
        "keeps a resized span", (tester) async {
      const stored = BoardSpan(
        rowStart: 3,
        rowSpan: 1,
        rowSpanFraction: 0.5,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(5, 50.0)),
        items: {"m": stored},
        snap: const BoardSnap.free(),
        resize: true,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 150.0, 40.0, 75.0),
      );
      _liftEdge(
        tester,
        s,
        const Offset(60.0, 223.0),
        BoardResizeEdges.trailing,
      );
      s.controller.rows = BoardAxisConfig(
        axis: s.controller.rows.axis,
        frozenEnd: 1,
      );
      await tester.pump();
      // Setup sanity: the lift point now lies in the gap above the new
      // footer, and the item still scrolls.
      final row = s.viewport.trackSampleAt(const Offset(60.0, 223.0))!.row;
      expect(row.band, isNull);
      expect(row.painted, 4.0);
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.none,
      );
      // TARGET.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("R22 a footer removed mid-hold over a short lattice keeps "
        "a resized span", (tester) async {
      const stored = BoardSpan(
        rowStart: 4,
        rowSpan: 0,
        rowSpanFraction: 0.5,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(5, 50.0), frozenEnd: 1),
        items: {"m": stored},
        resize: true,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 250.0, 40.0, 25.0),
      );
      _liftEdge(
        tester,
        s,
        const Offset(60.0, 273.0),
        BoardResizeEdges.trailing,
      );
      s.controller.rows = BoardAxisConfig(axis: s.controller.rows.axis);
      await tester.pump();
      // Setup sanity: the item now scrolls, and the lift point reads past
      // the lattice's end.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.none,
      );
      expect(
        s.viewport.trackSampleAt(const Offset(60.0, 273.0))!.row.painted,
        5.0,
      );
      // TARGET.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("R23 a footer added and removed mid-hold over a short "
        "lattice keeps a resized span", (tester) async {
      const stored = BoardSpan(
        rowStart: 4,
        rowSpan: 0,
        rowSpanFraction: 0.5,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(5, 50.0)),
        items: {"m": stored},
        snap: const BoardSnap.fraction(0.25),
        resize: true,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 200.0, 40.0, 25.0),
      );
      _liftEdge(
        tester,
        s,
        const Offset(60.0, 223.0),
        BoardResizeEdges.trailing,
      );
      s.controller.rows = BoardAxisConfig(
        axis: s.controller.rows.axis,
        frozenEnd: 1,
      );
      await tester.pump();
      // Setup sanity: the new footer pins the item, and the lift point
      // lies in the gap above it.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.trailing,
      );
      expect(
        s.viewport.trackSampleAt(const Offset(60.0, 223.0))!.row.band,
        isNull,
      );
      // TARGET, with the footer.
      expect(s.drag.currentTarget?.span, stored);
      s.controller.rows = BoardAxisConfig(axis: s.controller.rows.axis);
      await tester.pump();
      // TARGET, with the footer removed again.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("R24 rows added mid-hold beside a short lattice's footer "
        "keep a resized span", (tester) async {
      const stored = BoardSpan(
        rowStart: 4,
        rowSpan: 0,
        rowSpanFraction: 0.5,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(5, 50.0), frozenEnd: 1),
        items: {"m": stored},
        snap: const BoardSnap.fraction(0.25),
        resize: true,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 250.0, 40.0, 25.0),
      );
      _liftEdge(
        tester,
        s,
        const Offset(60.0, 273.0),
        BoardResizeEdges.trailing,
      );
      s.controller.rows = BoardAxisConfig(
        axis: UniformAxis(8, 50.0),
        frozenEnd: 1,
      );
      await tester.pump();
      // Setup sanity: the item now scrolls, and the lift point's scrolled
      // coordinate lies past the lift lattice's last row.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.none,
      );
      expect(
        s.viewport.trackSampleAt(const Offset(60.0, 273.0))!.row.scrolled,
        closeTo(5.46, 1e-9),
      );
      // TARGET.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("R25 rows of other extents added mid-hold beside a short "
        "lattice's footer keep a resized span", (tester) async {
      const stored = BoardSpan(
        rowStart: 4,
        rowSpan: 0,
        rowSpanFraction: 0.5,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(
          axis: ExplicitAxis(<double>[50.0, 50.0, 50.0, 50.0, 50.0]),
          frozenEnd: 1,
        ),
        items: {"m": stored},
        snap: const BoardSnap.fraction(0.25),
        resize: true,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 250.0, 40.0, 25.0),
      );
      _liftEdge(
        tester,
        s,
        const Offset(60.0, 273.0),
        BoardResizeEdges.trailing,
      );
      s.controller.rows = BoardAxisConfig(
        axis: ExplicitAxis(<double>[
          50.0, 50.0, 50.0, 50.0, 50.0, 80.0, 30.0, 80.0, //
        ]),
        frozenEnd: 1,
      );
      await tester.pump();
      // Setup sanity: the item now scrolls, and the lift point's scrolled
      // coordinate lies 23 px into the new 80 px row.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.none,
      );
      expect(
        s.viewport.trackSampleAt(const Offset(60.0, 273.0))!.row.scrolled,
        closeTo(5.2875, 1e-9),
      );
      // TARGET.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("R26 bands changed twice while content is scrolled away "
        "keep a resized span once it scrolls back", (tester) async {
      const stored = BoardSpan(rowStart: 12, colStart: 1);
      final s = await _setup(
        tester,
        rows: _rows(frozenEnd: 1),
        items: {"m": stored},
        verticalScroll: 500.0,
        snap: const BoardSnap.fraction(0.25),
        resize: true,
      );
      _expectRect(
        s.viewport.rectOfItem("m"),
        const Rect.fromLTWH(40.0, 100.0, 40.0, 50.0),
      );
      _liftEdge(
        tester,
        s,
        const Offset(60.0, 148.0),
        BoardResizeEdges.trailing,
      );
      final position = s.viewport.verticalPosition!;
      position.jumpTo(530.0);
      await tester.pump();
      s.controller.rows = BoardAxisConfig(axis: s.controller.rows.axis);
      await tester.pump();
      s.controller.rows = BoardAxisConfig(
        axis: s.controller.rows.axis,
        frozenEnd: 2,
      );
      await tester.pump();
      position.jumpTo(500.0);
      await tester.pump();
      // Setup sanity: the offset is the lift's again, and the lift point
      // lies in the scrolled region, where a sample reads the offset.
      expect(position.pixels, 500.0);
      expect(
        s.viewport.trackSampleAt(const Offset(60.0, 148.0))!.row.band,
        isNull,
      );
      // TARGET.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("R20 under overscroll a scrolled leading edge dragged into "
        "the header moves on without a jump", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: {"m": const BoardSpan(rowStart: 1, colStart: 1)},
        verticalDetails: const ScrollableDetails(
          direction: AxisDirection.down,
          physics: BouncingScrollPhysics(),
        ),
        snap: const BoardSnap.free(),
        resize: true,
      );
      // Held past the top: the spring back needs frames, and none is
      // pumped.
      s.viewport.verticalPosition!.jumpTo(-40.0);
      // Setup sanity: the offset holds past the top.
      expect(s.viewport.verticalPosition!.pixels, -40.0);
      _liftEdge(tester, s, const Offset(60.0, 92.0), BoardResizeEdges.leading);
      _update(tester, s, const Offset(60.0, 49.0));
      // TARGET.
      final target = s.drag.currentTarget?.span;
      expect(target?.startTrackOn(Axis.vertical), closeTo(0.94, 1e-9));
      expect(target?.endTrackOn(Axis.vertical), closeTo(2.0, 1e-9));
    });

    testWidgets("R27 an edge placed on a band's path whose span does not pin "
        "is placed again on the scrolled path", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 2),
        items: {"m": const BoardSpan(rowStart: 0, colStart: 1)},
        verticalScroll: 1000.0,
        snap: const BoardSnap.free(),
        resize: true,
      );
      _liftEdge(tester, s, const Offset(60.0, 25.0), BoardResizeEdges.trailing);
      _update(tester, s, const Offset(60.0, 95.0));
      // TARGET: the end is read in the scrolled lattice under the pointer.
      expect(
        s.drag.currentTarget?.span.endTrackOn(Axis.vertical),
        closeTo(22.4, 1e-9),
      );
    });

    Future<_Setup> pressedThroughFooter(WidgetTester tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenEnd: 2),
        items: {
          "m": const BoardSpan(
            rowStart: 25,
            rowFraction: 0.3,
            rowSpan: 3,
            colStart: 1,
          ),
        },
        verticalScroll: 975.0,
        snap: const BoardSnap.free(),
        resize: true,
      );
      // Setup sanity: the item scrolls, its top edge paints at y 290 under
      // the footer, whose cells build nothing, and the lift point reads
      // footer row 29.8 where the item's own lattice reads 25.3.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.none,
      );
      expect(s.viewport.rectOfItem("m")!.top, 290.0);
      final lift = s.viewport.trackSampleAt(const Offset(60.0, 290.0))!.row;
      expect(
        (lift.band, lift.painted, lift.scrolled),
        ((start: 28, end: 30), 29.8, 25.3),
      );
      _liftEdge(tester, s, const Offset(60.0, 290.0), BoardResizeEdges.leading);
      return s;
    }

    testWidgets("R28 a leading edge pressed through a footer and moved down "
        "keeps the span", (tester) async {
      final s = await pressedThroughFooter(tester);
      _update(tester, s, const Offset(60.0, 291.0));
      // TARGET: the edge stays in the item's lattice, where 25.32 is hidden
      // under the footer, so the stored span stands rather than the edge
      // jumping up into the footer.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(
          rowStart: 25,
          rowFraction: 0.3,
          rowSpan: 3,
          colStart: 1,
        ),
      );
    });

    testWidgets("R29 a leading edge pressed through a footer and moved up "
        "within it lands where the item shows", (tester) async {
      final s = await pressedThroughFooter(tester);
      _update(tester, s, const Offset(60.0, 250.0));
      // TARGET: the edge moves up in the item's lattice to 24.5, under the
      // footer, so it stops at 23.25, the last start on the grid that
      // shows above the footer's inner edge at 23.5, rather than the item
      // shrinking into the footer.
      expect(s.drag.currentTarget?.span.startTrackOn(Axis.vertical), 23.25);
    });

    testWidgets("R30 a leading edge pressed through a header and dragged onto "
        "the footer pins in the footer", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(
          axis: UniformAxis(30, 50.0),
          frozenStart: 1,
          frozenEnd: 2,
        ),
        items: {
          "m": const BoardSpan(
            rowStart: 0,
            rowFraction: 0.5,
            rowSpan: 28,
            rowSpanFraction: 0.5,
            colStart: 1,
          ),
        },
        verticalScroll: 10.0,
        snap: const BoardSnap.free(),
        resize: true,
      );
      // Setup sanity: the item scrolls, its top edge under the header.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.none,
      );
      expect(s.viewport.rectOfItem("m")!.top, 15.0);
      _liftEdge(tester, s, const Offset(60.0, 16.0), BoardResizeEdges.leading);
      _update(tester, s, const Offset(60.0, 250.0));
      // TARGET: the press went through the header, not the footer the
      // pointer is over now, so the footer's path puts the edge under the
      // pointer there and the span pins in the footer.
      expect(
        s.drag.currentTarget?.span.startTrackOn(Axis.vertical),
        closeTo(28.75, 1e-9),
      );
    });

    testWidgets("R31 a leading edge pressed through a footer and dragged down "
        "into its tracks keeps the span", (tester) async {
      const stored = BoardSpan(
        rowStart: 27,
        rowFraction: 0.8,
        rowSpan: 2,
        rowSpanFraction: 0.2,
        colStart: 1,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenEnd: 2),
        items: {"m": stored},
        verticalScroll: 1150.0,
        snap: const BoardSnap.free(),
        resize: true,
      );
      // Setup sanity: the top edge paints at y 240, under the footer.
      expect(s.viewport.rectOfItem("m")!.top, 240.0);
      _liftEdge(tester, s, const Offset(60.0, 242.0), BoardResizeEdges.leading);
      _update(tester, s, const Offset(60.0, 260.0));
      // TARGET: in the item's lattice the edge reaches 28.16, inside the
      // footer's tracks, where a pinned span would paint 32 px above where
      // the edge began. The span takes no pin from the footer's tracks,
      // and the shows bound keeps it.
      expect(s.drag.currentTarget?.span, stored);
    });

    testWidgets("R32 a leading edge pressed through a footer and dragged up "
        "under the track snap lands where the item shows", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenEnd: 2),
        items: {
          "m": const BoardSpan(
            rowStart: 27,
            rowFraction: 0.8,
            rowSpan: 0,
            rowSpanFraction: 0.7,
            colStart: 1,
          ),
        },
        verticalScroll: 1100.0,
        snap: const BoardSnap.track(),
        resize: true,
      );
      // Setup sanity: the item scrolls, its top edge under the footer.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.none,
      );
      expect(s.viewport.rectOfItem("m")!.top, 290.0);
      _liftEdge(tester, s, const Offset(60.0, 292.0), BoardResizeEdges.leading);
      _update(tester, s, const Offset(60.0, 250.0));
      // TARGET: the edge is placed in the item's lattice and stops at 25,
      // the last whole track that shows above the footer, where the
      // footer's path would floor it back onto its stored start.
      expect(s.drag.currentTarget?.span.startTrackOn(Axis.vertical), 25.0);
    });

    testWidgets("R33 a trailing edge pressed through a header at scroll 0 and "
        "dragged up pins in the header", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
        items: {
          "m": const BoardSpan(
            rowStart: 0,
            rowSpan: 1,
            rowSpanFraction: 0.16,
            colStart: 1,
          ),
        },
        snap: const BoardSnap.free(),
        resize: true,
      );
      // Setup sanity: the item scrolls, its bottom edge at y 58, and at the
      // lift point under the header the header's coordinate and the
      // item's agree.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.none,
      );
      expect(s.viewport.rectOfItem("m")!.bottom, closeTo(58.0, 1e-9));
      final lift = s.viewport.trackSampleAt(const Offset(60.0, 48.0))!.row;
      expect((lift.band, lift.painted), ((start: 0, end: 1), lift.scrolled));
      _liftEdge(tester, s, const Offset(60.0, 48.0), BoardResizeEdges.trailing);
      _update(tester, s, const Offset(60.0, 30.0));
      // TARGET: where the two coordinates agree the header's path is the
      // item's own, so the edge follows the pointer and the span pins.
      expect(
        s.drag.currentTarget?.span.endTrackOn(Axis.vertical),
        closeTo(0.8, 1e-9),
      );
    });

    testWidgets("R34 a leading edge pressed through a footer at the scroll's "
        "end and dragged down pins in the footer", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenEnd: 2),
        items: {
          "m": const BoardSpan(
            rowStart: 27,
            rowFraction: 0.8,
            rowSpan: 1,
            rowSpanFraction: 0.2,
            colStart: 1,
          ),
        },
        verticalScroll: 1200.0,
        snap: const BoardSnap.free(),
        resize: true,
      );
      // Setup sanity: the item scrolls, its top edge at y 190, and at the
      // lift point under the footer the footer's coordinate and the
      // item's agree.
      expect(
        s.controller.pinOfId(s.controller.idOfKey("m"), Axis.vertical),
        BoardPin.none,
      );
      expect(s.viewport.rectOfItem("m")!.top, 190.0);
      final lift = s.viewport.trackSampleAt(const Offset(60.0, 201.0))!.row;
      expect(lift.band, (start: 28, end: 30));
      expect(
        (lift.painted - lift.scrolled).abs(),
        lessThanOrEqualTo(precisionErrorTolerance),
      );
      _liftEdge(tester, s, const Offset(60.0, 201.0), BoardResizeEdges.leading);
      _update(tester, s, const Offset(60.0, 240.0));
      // TARGET: the footer's path is the item's own here, so the edge
      // follows the pointer and the span pins.
      expect(
        s.drag.currentTarget?.span.startTrackOn(Axis.vertical),
        closeTo(28.58, 1e-9),
      );
    });
  });

  group("cells over a band", () {
    testWidgets("C1 resolveDropCell in the header's lower half answers "
        "the header", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenStart: 1),
        items: const {},
        cellBuilder: _plainCell,
        verticalScroll: 1000.0,
      );
      // TARGET.
      expect(s.viewport.resolveDropCell(const Offset(60.0, 35.0)).row, 0);
    });

    testWidgets("C2 resolveDropCell beside the footer answers a row that "
        "shows", (tester) async {
      final s = await _setup(
        tester,
        rows: _rows(frozenEnd: 1),
        items: const {},
      );
      // TARGET.
      expect(s.viewport.resolveDropCell(const Offset(60.0, 240.0)).row, 4);
    });

    testWidgets("C3 a quarter-snap tap in the header's lower half selects "
        "the header", (tester) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(40, 50.0), frozenStart: 1),
      );
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(
            controller: controller,
            verticalDetails: ScrollableDetails.vertical(controller: vertical),
            cellBuilder: _nullCell,
            selection: BoardSelectionConfig(
              mode: BoardSelectionMode.cell,
              snap: const BoardSnap.fraction(0.25),
              onChanged: (selection) {},
            ),
          ),
        ),
      );
      vertical.jumpTo(200.0);
      await tester.pump();
      await tester.tapAt(_global(tester, const Offset(60.0, 45.0)));
      await tester.pump();
      // TARGET.
      expect(controller.selection.value.anchor, (row: 0, col: 1));
    });

    testWidgets("C4 a quarter-snap tap beside the footer selects a row "
        "that shows", (tester) async {
      final controller = _controller(tester, rows: _rows(frozenEnd: 1));
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: _nullCell,
            selection: BoardSelectionConfig(
              mode: BoardSelectionMode.cell,
              snap: const BoardSnap.fraction(0.25),
              onChanged: (selection) {},
            ),
          ),
        ),
      );
      await tester.tapAt(_global(tester, const Offset(60.0, 245.0)));
      await tester.pump();
      // TARGET.
      expect(controller.selection.value.anchor, (row: 4, col: 1));
    });

    testWidgets("C5 frozenCellAt answers over a frozen column", (tester) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(30, 40.0), frozenStart: 1),
      );
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(controller: controller, cellBuilder: _plainCell),
        ),
      );
      final viewport = _viewport(tester);
      viewport.horizontalPosition!.jumpTo(400.0);
      await tester.pump();
      // TARGET.
      expect(viewport.frozenCellAt(const Offset(20.0, 120.0)), (
        row: 2,
        col: 0,
      ));
    });

    testWidgets("C6 the pixel row at the header's inner edge maps to the "
        "scrolled lattice", (tester) async {
      final controller = _controller(tester, rows: _rows(frozenStart: 1));
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(controller: controller, cellBuilder: _plainCell),
        ),
      );
      final viewport = _viewport(tester);
      viewport.verticalPosition!.jumpTo(1000.0);
      await tester.pump();
      // TARGET.
      expect(viewport.trackSpaceAt(const Offset(60.0, 50.0))!.row, 21.0);
      expect(viewport.resolveDropCell(const Offset(60.0, 50.0)).row, 21);
    });

    testWidgets("C7 the pixel row at the footer's inner edge maps to the "
        "footer", (tester) async {
      final controller = _controller(tester, rows: _rows(frozenEnd: 1));
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(controller: controller, cellBuilder: _plainCell),
        ),
      );
      final viewport = _viewport(tester);
      // TARGET.
      expect(viewport.trackSpaceAt(const Offset(60.0, 250.0))!.row, 29.0);
      expect(viewport.resolveDropCell(const Offset(60.0, 250.0)).row, 29);
    });

    testWidgets("C8 past a short lattice's end the painted coordinate is "
        "the lattice's end", (tester) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(3, 50.0)),
      );
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(controller: controller, cellBuilder: _plainCell),
        ),
      );
      // TARGET.
      expect(
        _viewport(tester).trackSpaceAt(const Offset(60.0, 250.0))!.row,
        3.0,
      );
    });

    testWidgets("C9 frozenCellAt past the viewport beside a header answers "
        "no cell", (tester) async {
      final controller = _controller(tester, rows: _rows(frozenStart: 1));
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(controller: controller, cellBuilder: _plainCell),
        ),
      );
      // TARGET.
      expect(_viewport(tester).frozenCellAt(const Offset(60.0, -10.0)), isNull);
    });

    testWidgets("C10 a range extended into a short lattice's gap ends on the "
        "last scrolled row under the track snap", (tester) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(5, 50.0), frozenEnd: 1),
      );
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: _plainCell,
            selection: BoardSelectionConfig(
              mode: BoardSelectionMode.range,
              onChanged: (selection) {},
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        _global(tester, const Offset(60.0, 75.0)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(_global(tester, const Offset(60.0, 225.0)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      // Setup sanity: the range starts on row 1.
      expect(controller.selection.value.anchor, (row: 1, col: 1));
      // TARGET: the gap above the footer resolves among the scrolled cells
      // that show, so the range ends on row 3, not the footer's row 4.
      expect(controller.selection.value.focus, (row: 3, col: 1));
    });
  });

  group("the drop fit's region on a board with no band", () {
    testWidgets("F5 a refused lift of a half-track laned chip measures the "
        "widened box, columns 0 to 2", (tester) async {
      const chip = BoardSpan(
        rowStart: 8,
        colStart: 1,
        colFraction: 0.5,
        colSpan: 0,
        colSpanFraction: 0.5,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(24, 60.0)),
        columns: BoardAxisConfig(
          axis: UniformAxis(7, 170.0),
          laneExtent: 170.0,
        ),
        items: {
          "m": chip,
          "o": chip,
          "p": const BoardSpan(rowStart: 8, colStart: 0),
        },
        dropFit: const BoardDropFit(
          minFreeFraction: 0.55,
          rowRadius: 0.0,
          colRadius: 1.0,
        ),
        canDropAt: _noOverlap,
        verticalScroll: 400.0,
      );
      // Setup sanity: the chip is laned, so its columns step by whole
      // tracks, and its own placement is refused.
      expect(s.controller.isLanedId(s.controller.idOfKey("m")), isTrue);
      _lift(tester, s, s.viewport.rectOfItem("m")!.center);
      expect(s.asked.first, chip);
      // TARGET: the region is columns 0 to 2, half free, so the gate
      // stays closed.
      expect(s.drag.currentTarget, isNull);
    });

    testWidgets(
      "F7 a widened box whose far end is a track edge is measured to that "
      "edge",
      (tester) async {
        final s = await _setup(
          tester,
          rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
          items: {
            "m": const BoardSpan(
              rowStart: 1,
              rowFraction: 0.2,
              rowSpan: 1,
              rowSpanFraction: 0.2,
              colStart: 1,
            ),
            "p": const BoardSpan(
              rowStart: 2,
              rowSpan: 0,
              rowSpanFraction: 0.4,
              colStart: 1,
            ),
            "q": const BoardSpan(rowStart: 3, colStart: 1),
          },
          snap: const BoardSnap.free(),
          dropFit: const BoardDropFit(
            minFreeFraction: 0.75,
            rowRadius: 0.6,
            colRadius: 0.0,
          ),
          canDropAt: _noOverlap,
        );
        // Setup sanity: the box's end plus the radius is row 3's edge, and
        // the lift's own placement is refused.
        expect(
          s.controller.spanOf("m")!.endTrackOn(Axis.vertical) + 0.6,
          closeTo(3.0, 1e-9),
        );
        _lift(tester, s, const Offset(60.0, 90.0));
        expect(s.asked.first, s.controller.spanOf("m"));
        // TARGET: the region is rows 0 to 3, "q" in row 3 counted, 0.65
        // free, so the gate stays closed.
        expect(s.drag.currentTarget?.span, isNull);
      },
    );

    testWidgets(
      "F8 a kept box running past the lattice's end gathers the occupants "
      "of the starts its candidates clamp to",
      (tester) async {
        final s = await _setup(
          tester,
          rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
          items: {
            "m": const BoardSpan(
              rowStart: 5,
              colStart: 1,
              rowSpan: 2,
              rowSpanFraction: 0.5,
            ),
            "p": const BoardSpan(rowStart: 5, colStart: 1),
            "o0": const BoardSpan(rowStart: 3, colStart: 0),
            "o2": const BoardSpan(rowStart: 3, colStart: 2),
          },
          dropFit: const BoardDropFit(
            minFreeFraction: 0.0,
            rowRadius: 1.0,
            colRadius: 1.0,
          ),
          canDropAt: (controller, key, span) {
            return span.rowStart < 5;
          },
        );
        // Setup sanity: the item runs past the six rows, paints in row 5,
        // and its own placement is asked as it is stored.
        expect(s.controller.spanOf("m")!.endTrackOn(Axis.vertical), 7.5);
        expect(s.viewport.rectOfItem("m")!.top, closeTo(250.0, 1e-9));
        _lift(tester, s, const Offset(60.0, 275.0));
        expect(s.asked.first, s.controller.spanOf("m"));
        // TARGET: every row candidate clamps to 3.5, which "o0" and "o2"
        // occupy at the columns "p" leaves open, so none reaches the app
        // and nothing is admitted.
        expect(
          s.asked.where((span) {
            return span.rowStart < 5;
          }),
          isEmpty,
        );
        expect(s.drag.currentTarget?.span, isNull);
      },
    );

    testWidgets(
      "F11 a refused box a shrink mid-hold leaves past the lattice's end "
      "lands on the last row",
      (tester) async {
        final s = await _setup(
          tester,
          rows: BoardAxisConfig(axis: UniformAxis(10, 50.0)),
          items: {
            "m": const BoardSpan(rowStart: 4, colStart: 1),
            "o": const BoardSpan(rowStart: 4, colStart: 1),
          },
          dropFit: const BoardDropFit(
            minFreeFraction: 0.0,
            rowRadius: 0.0,
            colRadius: 1.0,
          ),
          canDropAt: _noOverlap,
        );
        _lift(tester, s, const Offset(60.0, 225.0));
        // Setup sanity: the lift's own placement is refused and nudged one
        // column left.
        expect(
          s.drag.currentTarget?.span,
          const BoardSpan(rowStart: 4, colStart: 0),
        );
        s.controller.rows = BoardAxisConfig(axis: UniformAxis(3, 50.0));
        await tester.pump();
        // TARGET: the kept row lies past the three rows; moved onto the
        // last row it is admitted there, and nothing throws.
        expect(tester.takeException(), isNull);
        expect(
          s.drag.currentTarget?.span,
          const BoardSpan(rowStart: 2, colStart: 1),
        );
      },
    );

    testWidgets("F12 a refused lift of an item past the lattice's end lands "
        "on the last row", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {
          "m": const BoardSpan(rowStart: 7, colStart: 1),
          "o": const BoardSpan(rowStart: 7, colStart: 1),
        },
        dropFit: const BoardDropFit(
          minFreeFraction: 0.0,
          rowRadius: 0.0,
          colRadius: 1.0,
        ),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(60.0, 290.0));
      // Setup sanity: the lift's own placement, the stored span, is asked.
      expect(s.asked.first, const BoardSpan(rowStart: 7, colStart: 1));
      // TARGET: the stored row lies past the six rows; moved onto the
      // last row it is admitted there.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 5, colStart: 1),
      );
    });

    testWidgets(
      "F13 a box a shrink mid-hold leaves past the lattice's end, refused "
      "on the last row, is nudged from there",
      (tester) async {
        final s = await _setup(
          tester,
          rows: BoardAxisConfig(axis: UniformAxis(10, 50.0)),
          items: {
            "m": const BoardSpan(rowStart: 4, colStart: 1),
            "o": const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 4),
          },
          dropFit: const BoardDropFit(minFreeFraction: 0.0),
          canDropAt: _noOverlap,
        );
        _lift(tester, s, const Offset(60.0, 225.0));
        // Setup sanity: the lift's own placement is refused and nudged one
        // column left.
        expect(
          s.drag.currentTarget?.span,
          const BoardSpan(rowStart: 4, colStart: 0),
        );
        s.controller.rows = BoardAxisConfig(axis: UniformAxis(3, 50.0));
        await tester.pump();
        // TARGET: moved onto the last row the box meets "o", so the nudge
        // searches from there and finds the column to its left, and
        // nothing throws.
        expect(tester.takeException(), isNull);
        expect(
          s.drag.currentTarget?.span,
          const BoardSpan(rowStart: 2, colStart: 0),
        );
      },
    );

    testWidgets("F14 a refused lift of an item past the lattice's end, "
        "refused on the last row, is nudged from there", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {
          "m": const BoardSpan(rowStart: 7, colStart: 1),
          "o": const BoardSpan(rowStart: 4, colStart: 1, rowSpan: 4),
        },
        dropFit: const BoardDropFit(minFreeFraction: 0.0),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(60.0, 290.0));
      // Setup sanity: the lift's own placement, the stored span, is asked.
      expect(s.asked.first, const BoardSpan(rowStart: 7, colStart: 1));
      // TARGET: moved onto the last row the box meets "o", and of the two
      // columns beside it the nudge takes the left.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 5, colStart: 0),
      );
    });

    testWidgets(
      "F15 a refused box a shrink mid-hold leaves exactly at the lattice's "
      "end lands on the last row",
      (tester) async {
        final s = await _setup(
          tester,
          rows: BoardAxisConfig(axis: UniformAxis(10, 50.0)),
          items: {
            "m": const BoardSpan(rowStart: 4, colStart: 1),
            "o": const BoardSpan(rowStart: 4, colStart: 1),
          },
          dropFit: const BoardDropFit(
            minFreeFraction: 0.0,
            rowRadius: 0.0,
            colRadius: 1.0,
          ),
          canDropAt: _noOverlap,
        );
        _lift(tester, s, const Offset(60.0, 225.0));
        // Setup sanity: the lift's own placement is refused and nudged one
        // column left.
        expect(
          s.drag.currentTarget?.span,
          const BoardSpan(rowStart: 4, colStart: 0),
        );
        s.controller.rows = BoardAxisConfig(axis: UniformAxis(4, 50.0));
        await tester.pump();
        // TARGET: the kept row starts at the four rows' end; moved onto the
        // last row it is admitted there, and nothing throws.
        expect(tester.takeException(), isNull);
        expect(
          s.drag.currentTarget?.span,
          const BoardSpan(rowStart: 3, colStart: 1),
        );
      },
    );

    testWidgets(
      "F16 a box a shrink mid-hold leaves exactly at the lattice's end, "
      "refused on the last row, is nudged from there",
      (tester) async {
        final s = await _setup(
          tester,
          rows: BoardAxisConfig(axis: UniformAxis(10, 50.0)),
          items: {
            "m": const BoardSpan(rowStart: 4, colStart: 1),
            "o": const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 4),
          },
          dropFit: const BoardDropFit(minFreeFraction: 0.0),
          canDropAt: _noOverlap,
        );
        _lift(tester, s, const Offset(60.0, 225.0));
        // Setup sanity: the lift's own placement is refused and nudged one
        // column left.
        expect(
          s.drag.currentTarget?.span,
          const BoardSpan(rowStart: 4, colStart: 0),
        );
        s.controller.rows = BoardAxisConfig(axis: UniformAxis(4, 50.0));
        await tester.pump();
        // TARGET: moved onto the last row the box meets "o", so the nudge
        // searches from there and finds the column to its left.
        expect(
          s.drag.currentTarget?.span,
          const BoardSpan(rowStart: 3, colStart: 0),
        );
      },
    );

    testWidgets("F17 a refused lift of an item past the columns' end lands "
        "on the last column", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {
          "m": const BoardSpan(rowStart: 2, colStart: 8),
          "o": const BoardSpan(rowStart: 2, colStart: 8),
        },
        dropFit: const BoardDropFit(
          minFreeFraction: 0.0,
          rowRadius: 1.0,
          colRadius: 0.0,
        ),
        canDropAt: (controller, key, span) {
          return span.colStart < 7;
        },
      );
      _lift(tester, s, const Offset(270.0, 125.0));
      // Setup sanity: the lift's own placement, the stored span, is asked.
      expect(s.asked.first, const BoardSpan(rowStart: 2, colStart: 8));
      // TARGET: the stored column lies past the seven columns; moved onto
      // the last column it is admitted there.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 2, colStart: 6),
      );
    });

    testWidgets("F18 a refused lift of an item past the columns' end, "
        "refused on the last column, is nudged from there", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {
          "m": const BoardSpan(rowStart: 2, colStart: 8),
          "o": const BoardSpan(rowStart: 2, colStart: 5, colSpan: 4),
        },
        dropFit: const BoardDropFit(minFreeFraction: 0.0),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(270.0, 125.0));
      // Setup sanity: the lift's own placement, the stored span, is asked.
      expect(s.asked.first, const BoardSpan(rowStart: 2, colStart: 8));
      // TARGET: moved onto the last column the box meets "o", so the
      // nudge searches from there and, of the rows beside it, takes the
      // one above.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 1, colStart: 6),
      );
    });

    testWidgets("F25 a moved box refused on the last row is gated and nudged "
        "as the moved box", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {
          "m": const BoardSpan(rowStart: 7, colStart: 1),
          "o": const BoardSpan(rowStart: 7, colStart: 1),
          "q": const BoardSpan(rowStart: 5, colStart: 1),
        },
        dropFit: const BoardDropFit(
          minFreeFraction: 0.0,
          rowRadius: 0.0,
          colRadius: 1.0,
        ),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(60.0, 290.0));
      // TARGET: on the last row the moved box meets "q", which the stored
      // box past the end does not, so the gate opens on the moved box and
      // the nudge finds the column to its left.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 5, colStart: 0),
      );
    });

    testWidgets("F26 a throw asking about the moved box ends the fit", (
      tester,
    ) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {
          "m": const BoardSpan(rowStart: 7, colStart: 1),
          "o": const BoardSpan(rowStart: 7, colStart: 1),
          "q": const BoardSpan(rowStart: 5, colStart: 1),
        },
        dropFit: const BoardDropFit(minFreeFraction: 0.0),
        canDropAt: (controller, key, span) {
          if (span.rowStart == 5 && span.colStart == 1) {
            throw StateError("refused by a throw");
          }
          return _noOverlap(controller, key, span);
        },
      );
      _lift(tester, s, const Offset(60.0, 290.0));
      // TARGET: the throw is reported and refuses, with no nudge.
      expect(tester.takeException(), isA<StateError>());
      expect(s.drag.currentTarget, isNull);
    });

    testWidgets("F27 under a track snap a box moved onto the lattice lands "
        "on a whole track", (tester) async {
      const box = BoardSpan(
        rowStart: 7,
        colStart: 1,
        rowSpan: 1,
        rowSpanFraction: 0.5,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {"m": box, "o": box},
        dropFit: const BoardDropFit(
          minFreeFraction: 0.0,
          rowRadius: 0.0,
          colRadius: 1.0,
        ),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(60.0, 290.0));
      // TARGET: the last start that holds the 1.5-track span is 4.5, which
      // the track snap floors to 4, as a drag to the end places it.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(
          rowStart: 4,
          colStart: 1,
          rowSpan: 1,
          rowSpanFraction: 0.5,
        ),
      );
    });

    testWidgets("F28 the move onto the lattice runs under zero radii", (
      tester,
    ) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {
          "m": const BoardSpan(rowStart: 7, colStart: 1),
          "o": const BoardSpan(rowStart: 7, colStart: 1),
        },
        dropFit: const BoardDropFit(
          minFreeFraction: 0.0,
          rowRadius: 0.0,
          colRadius: 0.0,
        ),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(60.0, 290.0));
      // TARGET: a policy with no step still moves the box onto the last
      // row, where it is admitted.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 5, colStart: 1),
      );
    });

    testWidgets("F29 the move onto the lattice runs under a minFreeFraction "
        "of 1.0", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {
          "m": const BoardSpan(rowStart: 7, colStart: 1),
          "o": const BoardSpan(rowStart: 7, colStart: 1),
        },
        dropFit: const BoardDropFit(minFreeFraction: 1.0),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(60.0, 290.0));
      // TARGET: the policy that disables the slide still moves the box.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 5, colStart: 1),
      );
    });

    testWidgets("F30 the move onto the lattice runs for a refusal that meets "
        "no occupant", (tester) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {"m": const BoardSpan(rowStart: 7, colStart: 1)},
        dropFit: const BoardDropFit(minFreeFraction: 0.0),
        canDropAt: (controller, key, span) {
          return span.rowStart < 6;
        },
      );
      _lift(tester, s, const Offset(60.0, 290.0));
      // Setup sanity: the stored box is asked first, and refused.
      expect(s.asked.first, const BoardSpan(rowStart: 7, colStart: 1));
      // TARGET: the gate's first term would leave a refusal for an app
      // rule standing; the move runs before it.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 5, colStart: 1),
      );
    });

    testWidgets("F31 under a fraction snap a box moved onto the lattice "
        "keeps the window's last start", (tester) async {
      const box = BoardSpan(
        rowStart: 7,
        colStart: 1,
        rowSpan: 1,
        rowSpanFraction: 0.5,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {"m": box, "o": box},
        snap: const BoardSnap.fraction(0.35),
        dropFit: const BoardDropFit(
          minFreeFraction: 0.0,
          rowRadius: 0.0,
          colRadius: 1.0,
        ),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(60.0, 290.0));
      // TARGET: only a track snap floors; 4.5, the last start that holds
      // the span, stands, as a drag to the end places it.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(
          rowStart: 4,
          rowFraction: 0.5,
          colStart: 1,
          rowSpan: 1,
          rowSpanFraction: 0.5,
        ),
      );
    });

    testWidgets("F19 control: a refused box in the last row is nudged", (
      tester,
    ) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {
          "m": const BoardSpan(rowStart: 5, colStart: 1),
          "o": const BoardSpan(rowStart: 5, colStart: 1),
        },
        dropFit: const BoardDropFit(
          minFreeFraction: 0.0,
          rowRadius: 1.0,
          colRadius: 0.0,
        ),
        canDropAt: _noOverlap,
      );
      _lift(tester, s, const Offset(60.0, 275.0));
      // TARGET: a box that ends at the lattice's end starts inside it, so
      // it is nudged a row up.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 4, colStart: 1),
      );
    });

    testWidgets("F20 control: a refused box running past the lattice's end "
        "is nudged", (tester) async {
      const box = BoardSpan(
        rowStart: 5,
        colStart: 1,
        rowSpan: 1,
        rowSpanFraction: 0.5,
      );
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        items: {"m": box, "p": const BoardSpan(rowStart: 5, colStart: 1)},
        dropFit: const BoardDropFit(
          minFreeFraction: 0.0,
          rowRadius: 0.0,
          colRadius: 1.0,
        ),
        canDropAt: (controller, key, span) {
          return span.colStart != 1;
        },
      );
      _lift(tester, s, const Offset(60.0, 275.0));
      // TARGET: a box that starts inside the lattice and ends past it is
      // nudged a column left.
      expect(s.drag.currentTarget?.span, box.copyWith(colStart: 0));
    });

    testWidgets("F22 a box longer than the lattice is nudged within it", (
      tester,
    ) async {
      final s = await _setup(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(3, 50.0)),
        items: {
          "m": const BoardSpan(rowStart: 0, rowSpan: 4, colStart: 1),
          "o": const BoardSpan(rowStart: 0, colStart: 1),
        },
        dropFit: const BoardDropFit(minFreeFraction: 0.0),
        canDropAt: (controller, key, span) {
          return span.colStart != 1;
        },
      );
      _lift(tester, s, const Offset(60.0, 75.0));
      // TARGET: the row window of a span longer than the lattice is
      // inverted, and the clamp answers its lower bound, row 0, so the
      // nudge keeps a start inside the lattice.
      expect(
        s.drag.currentTarget?.span,
        const BoardSpan(rowStart: 0, rowSpan: 4, colStart: 0),
      );
    });
  });

  testWidgets("F6 a radius off the track grid measures the widened box", (
    tester,
  ) async {
    const chip = BoardSpan(
      rowStart: 8,
      colStart: 1,
      colFraction: 0.5,
      colSpan: 0,
      colSpanFraction: 0.5,
    );
    final s = await _setup(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(24, 60.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 170.0), laneExtent: 170.0),
      items: {
        "m": chip,
        "o": chip,
        "p": const BoardSpan(rowStart: 8, colStart: 0),
      },
      dropFit: const BoardDropFit(
        minFreeFraction: 0.55,
        rowRadius: 0.0,
        colRadius: 1.25,
      ),
      canDropAt: _noOverlap,
      verticalScroll: 400.0,
    );
    expect(s.controller.isLanedId(s.controller.idOfKey("m")), isTrue);
    _lift(tester, s, s.viewport.rectOfItem("m")!.center);
    expect(s.asked.first, chip);
    expect(
      s.drag.currentTarget?.span,
      const BoardSpan(rowStart: 8, colStart: 2, colSpan: 0, colSpanFraction: 0.5),
    );
  });
}
