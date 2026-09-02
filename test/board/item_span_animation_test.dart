/// Tests for the item span animation plan: a span change is a RECT FLIP,
/// so the item paints its old rectangle on the frame of the mutation and
/// corner and extent decay together to the new one, for the item and for
/// the neighbours the mutation re-lanes.
///
/// Source: `plans/2026-09-02-item-span-animation-plan.md`, the Testing
/// Plan section (anchor `testing-plan`). Case names are the plan's names
/// VERBATIM.
///
/// Every case failed at the assertion marked TARGET before its landing
/// step, on the tree the case names or against the scratch variant its
/// comment names, with every setup sanity assertion before it passing.
///
/// Clock cadence: a case installs, pumps once with no duration (the
/// install frame; a ticker's first tick reports elapsed zero,
/// `scheduler/ticker.dart:276`), then pumps durations, so "at 100ms"
/// means that second pump.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/_item_slide_engine.dart';
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

const Key _frameKey = ValueKey<String>("board-frame");

const BoardAnimationSpec _ms200 = BoardAnimationSpec(
  duration: Duration(milliseconds: 200),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

/// itemSlide live, every other family off, so a case observes the FLIP
/// alone and no enter ramp or track resize runs beside it.
const BoardAnimationStyle _slideOnly = BoardAnimationStyle(
  trackResize: _zero,
  itemSlide: _ms200,
  itemEnterExit: _zero,
);

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

/// PLAIN: six 50px rows by seven 40px columns, no lane axis.
BoardController<String, _Item> _plain(
  WidgetTester tester, {
  BoardAnimationStyle style = _slideOnly,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _board(
  BoardController<String, _Item> controller, {
  double width = 280.0,
  double height = 300.0,
  double cellHeight = 50.0,
  ScrollController? horizontal,
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
            horizontalDetails: horizontal == null
                ? const ScrollableDetails.horizontal()
                : ScrollableDetails.horizontal(controller: horizontal),
            cellBuilder: (context, cell) {
              return SizedBox(width: 40.0, height: cellHeight);
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

/// FIXED-LANE: the same rows, and columns carrying a lane extent with no
/// padding, so a day slices to 40 alone and 20 shared.
BoardController<String, _Item> _fixedLane(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
    columns: BoardAxisConfig(
      axis: UniformAxis(7, 40.0),
      laneExtent: 18.0,
      lanePadding: 0.0,
    ),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: _slideOnly,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// CONTENT-LANE: the lattice of `make_room_track_sizing_test.dart`, rows
/// content-sized and carrying the lanes.
BoardController<String, _Item> _contentLane(
  WidgetTester tester,
  BoardAnimationStyle style,
) {
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

/// Row 0 holds `f`; row 2 holds `a`, `b`, `c` on lanes 0, 1 and 2. A copy
/// of the relaning fixture in `make_room_track_sizing_test.dart`: moving
/// `b` out re-lanes `c` from lane 2 to lane 1.
void _addRelaningFixture(BoardController<String, _Item> controller) {
  controller.addItem(
    const _Item("f"),
    const BoardSpan(rowStart: 0, colStart: 1, colSpan: 3),
  );
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 2, colStart: 0, colSpan: 5),
  );
  controller.addItem(
    const _Item("b"),
    const BoardSpan(rowStart: 2, colStart: 1, colSpan: 3),
  );
  controller.addItem(
    const _Item("c"),
    const BoardSpan(rowStart: 2, colStart: 2, colSpan: 4),
  );
}

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

/// A drag controller on [config], torn down with the test.
BoardDragController<String> _drag(
  WidgetTester tester,
  BoardController<String, _Item> controller,
  BoardDragConfig<String> config,
) {
  final drag = BoardDragController<String>(
    boardController: controller,
    vsync: tester,
    config: config,
  );
  addTearDown(drag.dispose);
  return drag;
}

/// itemSlide and makeRoom both live, for the resize preview cases.
const BoardAnimationStyle _previewStyle = BoardAnimationStyle(
  trackResize: _zero,
  itemSlide: _ms200,
  itemEnterExit: _zero,
  makeRoom: _ms200,
);

/// A trailing-edge resize session that commits through `resizeItem`.
BoardDragController<String> _resizeDrag(
  WidgetTester tester,
  BoardController<String, _Item> controller,
) {
  return _drag(
    tester,
    controller,
    BoardDragConfig<String>(
      autoScrollEdgeZone: 0.0,
      onItemMoved: (key, span) {},
      onItemResized: (key, span) {
        controller.resizeItem(key, span);
      },
      resizeEdges: BoardResizeEdges.trailing,
    ),
  );
}

RenderBoardViewport<String> _viewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

/// A vsync for the engine-level case, which owns no widget tree.
class _TestVSync implements TickerProvider {
  Ticker? ticker;

  @override
  Ticker createTicker(TickerCallback onTick) {
    return ticker = Ticker(onTick);
  }
}

void main() {
  // T0. The engine's own contract, the one case that reaches it directly
  // (no test imported `_item_slide_engine.dart` before this one).
  // Falsification: a `hasExtentActive` that scans `start` instead of
  // `startExtent` reports true for the lead-only install below.
  testWidgets("an engine record decays both deltas on one clock and "
      "reports an extent while one stands", (tester) async {
    final vsync = _TestVSync();
    var notifies = 0;
    final engine = ItemSlideEngine(
      vsync: vsync,
      styleOf: () {
        return _slideOnly;
      },
      notifyNow: () {
        notifies += 1;
      },
    );
    addTearDown(engine.dispose);

    expect(
      engine.animateSlideFrom(
        1,
        const Offset(10.0, 0.0),
        family: BoardAnimationFamily.itemSlide,
        extentDelta: const Offset(-20.0, 0.0),
      ),
      isTrue,
    );
    // Setup sanity: both deltas are at their install values, and the
    // engine reports the extent.
    expect(engine.deltaOf(1), const Offset(10.0, 0.0));
    expect(engine.extentDeltaOf(1), const Offset(-20.0, 0.0));
    // TARGET: the extent flag follows the extent, not the lead.
    expect(engine.hasExtentActive, isTrue);
    expect(engine.hasRelaneActive, isFalse);
    expect(engine.relaneDeltaOf(1), Offset.zero);

    // One clock: at 100ms of 200ms both are half way. The install
    // started the engine's ticker, so a bare pump is the install frame.
    expect(vsync.ticker!.isActive, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.deltaOf(1).dx, closeTo(5.0, 0.01));
    expect(engine.extentDeltaOf(1).dx, closeTo(-10.0, 0.01));
    expect(engine.hasExtentActive, isTrue);

    // The settle drops the record and the flag with it.
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.deltaOf(1), Offset.zero);
    expect(engine.extentDeltaOf(1), Offset.zero);
    expect(engine.hasExtentActive, isFalse);
    expect(notifies, greaterThan(0));

    // A LEAD-ONLY install leaves the extent flag false.
    engine.animateSlideFrom(
      2,
      const Offset(4.0, 0.0),
      family: BoardAnimationFamily.itemSlide,
    );
    expect(engine.hasExtentActive, isFalse);

    // A RELANE install reports its lead through relaneDeltaOf and sets
    // the relane flag.
    engine.animateSlideFrom(
      3,
      const Offset(0.0, 18.0),
      family: BoardAnimationFamily.itemSlide,
      relane: true,
    );
    expect(engine.relaneDeltaOf(3), const Offset(0.0, 18.0));
    expect(engine.hasRelaneActive, isTrue);

    // Composing a relane onto a NON-relane record drops the flag: the
    // composed lead is no longer an intra-track shift.
    engine.animateSlideFrom(
      2,
      const Offset(0.0, 18.0),
      family: BoardAnimationFamily.itemSlide,
      relane: true,
    );
    expect(engine.relaneDeltaOf(2), Offset.zero);
    // And composing a non-relane onto a relane record drops it too.
    engine.animateSlideFrom(
      3,
      const Offset(40.0, 0.0),
      family: BoardAnimationFamily.itemSlide,
    );
    expect(engine.relaneDeltaOf(3), Offset.zero);
    expect(engine.hasRelaneActive, isFalse);

    // A refused install drops BOTH deltas together (P6).
    final off = ItemSlideEngine(
      vsync: _TestVSync(),
      styleOf: () {
        return BoardAnimationStyle.disabled;
      },
      notifyNow: () {},
    );
    addTearDown(off.dispose);
    expect(
      off.animateSlideFrom(
        1,
        const Offset(10.0, 0.0),
        family: BoardAnimationFamily.itemSlide,
        extentDelta: const Offset(-20.0, 0.0),
      ),
      isFalse,
    );
    expect(off.deltaOf(1), Offset.zero);
    expect(off.extentDeltaOf(1), Offset.zero);
    expect(off.hasExtentActive, isFalse);

    // The records installed above are still in flight; purge stops the
    // ticker, which is what the widget-tree cases get from a settle.
    engine.purgeActive();
    expect(vsync.ticker!.isActive, isFalse);
  });

  // T1. AC: a resize animates the extent from the old size.
  // Falsification: an install that writes the span before capturing the
  // old extent produces a zero delta and fails the first assertion.
  testWidgets("resizeItem animates the extent from the old size on the "
      "itemSlide clock", (tester) async {
    final controller = _plain(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final id = controller.idOfKey("m");
    // Setup sanity: two columns of 40.
    expect(viewport.rectOfItem("m")!.width, 80.0);

    controller.resizeItem(
      "m",
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 4),
    );
    // TARGET, reader: the extent delta is old minus new, the lead zero.
    expect(controller.anim.extentDeltaOf(id), const Offset(-80.0, 0.0));
    expect(controller.anim.offsetOfItem(id), Offset.zero);

    // TARGET, render: the painted size runs 80 to 160 over 200ms.
    await tester.pump();
    expect(viewport.rectOfItem("m")!.width, closeTo(80.0, 0.01));
    expect(tester.getSize(find.byKey(_itemKey("m"))).width, closeTo(80.0, 0.01));
    await tester.pump(const Duration(milliseconds: 100));
    expect(viewport.rectOfItem("m")!.width, closeTo(120.0, 0.5));
    expect(
      tester.getSize(find.byKey(_itemKey("m"))).width,
      closeTo(120.0, 0.5),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(viewport.rectOfItem("m")!.width, closeTo(160.0, 0.01));
    expect(controller.anim.extentDeltaOf(id), Offset.zero);
    await tester.pumpAndSettle();
  });

  // T2. The leading edge moves and the trailing edge does not: the lead
  // and the extent are equal and opposite, on one clock.
  // Falsification: an implementation that installs the extent without
  // the lead, or on a second record, drifts the right edge.
  testWidgets("a leading-edge resize holds the trailing edge still",
      (tester) async {
    final controller = _plain(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 2, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final id = controller.idOfKey("m");
    final rightBefore = viewport.rectOfItem("m")!.right;
    // Setup sanity: columns 2 and 3, so 80 to 160.
    expect(viewport.rectOfItem("m")!.left, 80.0);
    expect(rightBefore, 160.0);

    // Grow the LEADING edge one column: colStart 1, colSpan 3.
    controller.resizeItem(
      "m",
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 3),
    );
    expect(controller.anim.offsetOfItem(id), const Offset(40.0, 0.0));
    expect(controller.anim.extentDeltaOf(id), const Offset(-40.0, 0.0));

    double paintedRight() {
      final rect = viewport.rectOfItem("m")!;
      return rect.left + controller.anim.offsetOfItem(id).dx + rect.width;
    }

    // TARGET: the painted right edge never moves.
    await tester.pump();
    expect(paintedRight(), closeTo(rightBefore, 0.01));
    await tester.pump(const Duration(milliseconds: 100));
    expect(paintedRight(), closeTo(rightBefore, 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(paintedRight(), closeTo(rightBefore, 0.01));
    await tester.pumpAndSettle();
  });

  // T3. A move between tracks of EQUAL extent stays what it is today: a
  // lead-only, paint-only slide.
  // Falsification: a `hasExtentActive` that counts every record (rather
  // than one with a non-zero startExtent) makes this move layout-driving
  // and fails the second assertion; it also reddens the moveItem case in
  // `animation_paint_only_test.dart`.
  testWidgets("moveItem between equal tracks keeps a lead-only slide and "
      "stays paint-only", (tester) async {
    final controller = _plain(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final id = controller.idOfKey("m");

    controller.moveItem(
      "m",
      const BoardSpan(rowStart: 3, colStart: 4, colSpan: 2),
    );
    // Setup sanity: the move installed a lead.
    expect(controller.anim.offsetOfItem(id), const Offset(-160.0, -150.0));
    // TARGET.
    expect(controller.anim.extentDeltaOf(id), Offset.zero);
    expect(controller.anim.hasLayoutDrivingAnimations, isFalse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.anim.extentDeltaOf(id), Offset.zero);
    expect(controller.anim.hasLayoutDrivingAnimations, isFalse);
    await tester.pumpAndSettle();
  });

  // T4. The extent is layout-driving and the child is laid out at the
  // animated size, which hit-testing then probes.
  // Falsification: omitting `hasExtentActive` from the layout-driving
  // union stops the layout count advancing, keeps the child at its
  // install-frame size, and makes the first probe return the key.
  testWidgets("an extent in flight lays the child out per tick and "
      "hit-tests at its painted size", (tester) async {
    final controller = _plain(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 4),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    // Setup sanity: four columns, 40 to 200.
    expect(viewport.rectOfItem("m")!.width, 160.0);

    // SHRINK to two columns: the painted rect is larger than the
    // structural one for the whole animation.
    controller.resizeItem(
      "m",
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
    );
    await tester.pump();
    final layoutsAfterInstall = viewport.debugPerformLayoutCount;
    await tester.pump(const Duration(milliseconds: 100));
    // TARGET: a layout per tick.
    expect(
      viewport.debugPerformLayoutCount,
      greaterThan(layoutsAfterInstall),
    );
    // Half way: painted width 120, structural 80.
    final rect = viewport.rectOfItem("m")!;
    expect(rect.width, closeTo(120.0, 0.5));
    final y = rect.center.dy;
    // TARGET: past the animated trailing edge, inside the OLD one.
    expect(viewport.itemAt(Offset(rect.left + 140.0, y)), isNull);
    // Inside the animated rect, past the new structural edge.
    expect(viewport.itemAt(Offset(rect.left + 100.0, y)), "m");
    await tester.pumpAndSettle();
  });

  // T6. A mutation re-lanes a neighbour, whose slice narrows: the
  // neighbour FLIPs from its old rectangle like the moved item does.
  // Falsification: without the neighbour install A steps to half a day
  // with no record at all.
  testWidgets("a mutation that re-lanes a neighbour slides and resizes "
      "the neighbour", (tester) async {
    final controller = _fixedLane(tester);
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 1, colStart: 2, rowSpan: 3),
    );
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 4, colStart: 3, rowSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final aId = controller.idOfKey("a");
    final bId = controller.idOfKey("b");
    // Setup sanity: each alone in its day, so each takes the full 40.
    expect(controller.laneCountOf("a"), 1);
    expect(tester.getSize(find.byKey(_itemKey("a"))).width, 40.0);

    // B joins A's day and overlaps it on the sweep axis: two lanes, A
    // first by the start sort, so A keeps lane 0 and B takes lane 1.
    controller.moveItem(
      "b",
      const BoardSpan(rowStart: 2, colStart: 2, rowSpan: 2),
    );
    expect(controller.laneOf("a"), 0);
    expect(controller.laneOf("b"), 1);
    // TARGET: A's slice halves through a record, its lane origin
    // unchanged, and B carries the same narrowing with its own move.
    expect(controller.anim.extentDeltaOf(aId), const Offset(20.0, 0.0));
    expect(controller.anim.offsetOfItem(aId), Offset.zero);
    expect(controller.anim.extentDeltaOf(bId), const Offset(20.0, 0.0));
    expect(controller.anim.offsetOfItem(bId), const Offset(20.0, 100.0));

    await tester.pump();
    expect(tester.getSize(find.byKey(_itemKey("a"))).width, closeTo(40.0, 0.01));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(find.byKey(_itemKey("a"))).width, closeTo(30.0, 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(find.byKey(_itemKey("a"))).width, closeTo(20.0, 0.01));
    expect(controller.anim.extentDeltaOf(aId), Offset.zero);
    await tester.pumpAndSettle();
  });

  // T6b. On a CONTENT-SIZED lane axis a re-laned neighbour's slide is
  // lead-only, so the track's edge follows it only if the sizing term
  // reads that lead AND the router lays out per tick for it.
  // Falsification: leaving the router's relane term out holds row 2 at
  // 58 until the settle; leaving the sizing term out runs the row on the
  // 600ms trackResize instead, reading about 55 at 100ms.
  testWidgets("a re-laned neighbour's slide holds its content-sized "
      "track's edge per tick", (tester) async {
    final controller = _contentLane(
      tester,
      const BoardAnimationStyle(
        trackResize: BoardAnimationSpec(
          duration: Duration(milliseconds: 600),
          curve: Curves.linear,
        ),
        itemSlide: _ms200,
        itemEnterExit: _zero,
      ),
    );
    _addRelaningFixture(controller);
    // 20px cells, so a row's extent is its lane term rather than its
    // cells: the lattice of `make_room_track_sizing_test.dart`.
    await tester.pumpWidget(_board(controller, cellHeight: 20.0));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final cId = controller.idOfKey("c");
    // Setup sanity: three lanes on row 2, one on row 0.
    expect(controller.laneOf("c"), 2);
    expect(viewport.rectOfCell(2, 0)!.height, 58.0);
    expect(viewport.rectOfCell(0, 0)!.height, 22.0);

    // `b` leaves row 2 for row 0, at columns 4 to 6: it TOUCHES `f`
    // (columns 1 to 3) without overlapping it, so row 0 keeps one lane
    // and installs no resize of its own.
    controller.moveItem(
      "b",
      const BoardSpan(rowStart: 0, colStart: 4, colSpan: 3),
    );
    expect(controller.laneOf("c"), 1);
    expect(controller.laneCountOf("b"), 1);
    // TARGET: the row holds its painted edge and follows the slide.
    expect(controller.anim.relaneDeltaOf(cId), const Offset(0.0, 18.0));
    await tester.pump();
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(58.0, 0.01));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(22.0, 0.01));
    expect(controller.anim.hasActiveTrackResize, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.anim.relaneDeltaOf(cId).dy, closeTo(9.0, 0.5));
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(49.0, 0.5));
    expect(controller.anim.hasActiveTrackResize, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(40.0, 0.01));
    expect(controller.anim.hasActiveTrackResize, isFalse);
    await tester.pumpAndSettle();
  });

  // T12. The drag layer's suppression must reach the `setItems` door,
  // which is the one the package's own week example reports through.
  // Falsification: a suppression that only guards `_reSpan` lets the
  // bulk install carry c's lead, and c jumps back a lane on the drop
  // frame.
  testWidgets("a commit reported through setItems over a settled gap "
      "keeps the neighbour where the preview held it", (tester) async {
    final controller = _contentLane(
      tester,
      const BoardAnimationStyle(trackResize: _zero, itemSlide: _ms200),
    );
    _addRelaningFixture(controller);
    // The app's model, re-sent whole on every report, as the week
    // example does.
    final spans = <String, BoardSpan>{
      "f": const BoardSpan(rowStart: 0, colStart: 1, colSpan: 3),
      "a": const BoardSpan(rowStart: 2, colStart: 0, colSpan: 5),
      "b": const BoardSpan(rowStart: 2, colStart: 1, colSpan: 3),
      "c": const BoardSpan(rowStart: 2, colStart: 2, colSpan: 4),
    };
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final cId = controller.idOfKey("c");
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        autoScrollEdgeZone: 0.0,
        onItemMoved: (key, span) {
          spans[key] = span;
          controller.setItems(
            spans.entries.map((entry) {
              return BoardPlacement<_Item>(_Item(entry.key), entry.value);
            }),
          );
        },
      ),
    );
    final lift = viewport.rectOfItem("b")!.center;
    expect(
      drag.startDrag(
        key: "b",
        renderPort: viewport,
        pointerGlobal: _global(tester, lift),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, Offset(lift.dx, 11.0)));
    await tester.pump();
    // Let the gap SETTLE, which is the arm that publishes no hand-off.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.anim.hasMakeRoomMotion, isFalse);
    final heldTop = tester.getRect(find.byKey(_itemKey("c"))).top;

    drag.endDrag(cancel: false);
    await tester.pump();
    // Setup sanity: the commit landed through setItems and re-laned c.
    expect(controller.spanOf("b")!.rowStart, 0);
    expect(controller.laneOf("c"), 1);
    // TARGET: nothing was handed on, and nothing moved c.
    expect(controller.anim.makeRoomHandOff, isNull);
    expect(controller.anim.relaneDeltaOf(cId), Offset.zero);
    expect(
      tester.getRect(find.byKey(_itemKey("c"))).top,
      closeTo(heldTop, 0.01),
    );
    await tester.pumpAndSettle();
  });

  // T9, rewritten for the resize extent preview: a SETTLED preview has
  // already shown the committed extent, so the commit is CONTINUOUS on
  // both halves. The de-lane fixture of `board_drag_test.dart`: growing
  // b past a re-ranks b into lane 0, so the corner correction is a real
  // intra-track lead and it cancels the FLIP's, while the extent needs
  // no continuation at all. Its mid-preview twin is T9b.
  // Falsification: without the preview the width is still 80 through the
  // drag and steps at the drop; without the report's extent suppression
  // it snaps back to 80 on the drop frame and re-animates.
  testWidgets("a committed resize on a laned item is continuous from its "
      "preview", (tester) async {
    final controller = _contentLane(
      tester,
      const BoardAnimationStyle(
        trackResize: _zero,
        itemSlide: BoardAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
        itemEnterExit: _zero,
      ),
    );
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 0, colStart: 2, colSpan: 2),
    );
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 0, colStart: 2, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller, cellHeight: 20.0));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final bId = controller.idOfKey("b");
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        autoScrollEdgeZone: 0.0,
        onItemMoved: (key, span) {},
        onItemResized: (key, span) {
          controller.resizeItem(key, span);
        },
        resizeEdges: BoardResizeEdges.trailing,
      ),
    );
    final edge = viewport.rectOfItem("b")!;
    // Setup sanity: two columns of 40.
    expect(edge.width, 80.0);
    expect(
      drag.startDrag(
        key: "b",
        renderPort: viewport,
        pointerGlobal: _global(tester, Offset(edge.right, edge.top + 2.0)),
        edge: BoardResizeEdges.trailing,
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, Offset(240.0, edge.top + 2.0)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Setup sanity: the preview SETTLED at the prospective four columns
    // while the model kept its two.
    expect(tester.getSize(find.byKey(_itemKey("b"))).width, closeTo(160.0, 0.01));
    expect(controller.spanOf("b")!.colSpan, 2);

    drag.endDrag(cancel: false);
    await tester.pump();
    // TARGET: nothing steps. The corner correction cancelled the FLIP's
    // lead, and the extent was already where the commit puts it.
    expect(controller.spanOf("b")!.colSpan, 4);
    expect(controller.anim.offsetOfItem(bId), Offset.zero);
    expect(controller.anim.extentDeltaOf(bId), Offset.zero);
    expect(tester.getSize(find.byKey(_itemKey("b"))).width, closeTo(160.0, 0.01));
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.getSize(find.byKey(_itemKey("b"))).width,
      closeTo(160.0, 0.01),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(_itemKey("b"))).width,
      closeTo(160.0, 0.01),
    );
  });

  // T9b. An UNLANED item's committed resize has a zero corner
  // correction, there being no de-lane hold to correct off, so the glide
  // runs only because an extent continuation stands. Released one frame
  // after the move, so the preview is barely started and the whole
  // remainder is what the glide carries: the MID-preview twin of T9. Its
  // dropSettle is explicit and longer than itemSlide, which is what
  // tells the two clocks apart.
  // Falsification: the early return on a zero correction drops the
  // continuation, so the extent stays on the 200ms itemSlide record and
  // the width is already 120 at 200ms.
  testWidgets("an unlaned resize drag composes its extent onto the glide",
      (tester) async {
    final controller = _plain(
      tester,
      style: const BoardAnimationStyle(
        trackResize: _zero,
        itemSlide: _ms200,
        itemEnterExit: _zero,
        dropSettle: BoardAnimationSpec(
          duration: Duration(milliseconds: 400),
          curve: Curves.linear,
        ),
      ),
    );
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final id = controller.idOfKey("m");
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        autoScrollEdgeZone: 0.0,
        onItemMoved: (key, span) {},
        onItemResized: (key, span) {
          controller.resizeItem(key, span);
        },
        resizeEdges: BoardResizeEdges.trailing,
      ),
    );
    final edge = viewport.rectOfItem("m")!;
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, Offset(edge.right, edge.center.dy)),
        edge: BoardResizeEdges.trailing,
      ),
      isTrue,
    );
    // One column outward: 80 to 120.
    drag.updateDrag(_global(tester, Offset(160.0, edge.center.dy)));
    await tester.pump();
    drag.endDrag(cancel: false);
    await tester.pump();
    // Setup sanity: the correction is zero, so only the extent record
    // can carry this.
    expect(controller.anim.offsetOfItem(id), Offset.zero);
    expect(controller.anim.extentDeltaOf(id), const Offset(-40.0, 0.0));
    // TARGET: the 400ms dropSettle clock, not the 200ms itemSlide one.
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.getSize(find.byKey(_itemKey("m"))).width,
      closeTo(100.0, 0.5),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.getSize(find.byKey(_itemKey("m"))).width,
      closeTo(120.0, 0.01),
    );
    await tester.pumpAndSettle();
  });

  // ------------------------------------------------------------------
  // The resize extent preview
  // (`plans/2026-09-02-resize-extent-preview-plan.md`).
  // ------------------------------------------------------------------

  // P1 and P2. The block follows the finger: the resolved span's extent
  // is PREVIEWED on the makeRoom clock while the pointer holds, without
  // the model being written, and it re-aims and closes like the gap.
  // Falsification: before the preview the painted width stays at its
  // structural 80 for the whole gesture, which is what the baseline
  // probe showed.
  testWidgets("a resize drag previews the prospective extent on the "
      "makeRoom clock", (tester) async {
    final controller = _plain(tester, style: _previewStyle);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final drag = _resizeDrag(tester, controller);
    double painted() {
      return tester.getSize(find.byKey(_itemKey("m"))).width;
    }

    final edge = viewport.rectOfItem("m")!;
    expect(painted(), 80.0);
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, Offset(edge.right, edge.center.dy)),
        edge: BoardResizeEdges.trailing,
      ),
      isTrue,
    );
    // Three columns outward: the resolver reports five columns, 200.
    drag.updateDrag(_global(tester, Offset(240.0, edge.center.dy)));
    await tester.pump();
    // Setup sanity: the target resolved and the MODEL is untouched.
    expect(drag.currentTarget!.span.colSpan, 5);
    expect(controller.spanOf("m")!.colSpan, 2);
    // TARGET: the painted extent animates onto the prospective one.
    expect(painted(), closeTo(80.0, 0.01));
    await tester.pump(const Duration(milliseconds: 100));
    expect(painted(), closeTo(140.0, 1.0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(painted(), closeTo(200.0, 0.01));
    expect(controller.spanOf("m")!.colSpan, 2);

    // P2, re-aim: back to four columns, from where it paints.
    drag.updateDrag(_global(tester, Offset(200.0, edge.center.dy)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 16));
    expect(painted(), closeTo(160.0, 0.01));

    // P2, cancel: the preview closes by animation, as the gap does.
    drag.endDrag(cancel: true);
    await tester.pump();
    expect(painted(), closeTo(160.0, 1.0));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 16));
    expect(painted(), closeTo(80.0, 0.01));
    expect(controller.spanOf("m")!.colSpan, 2);
    await tester.pumpAndSettle();
  });

  // P3. The commit is CONTINUOUS: what the preview showed, the report
  // does not re-animate. The report's own FLIP does install the whole
  // 80-to-200 change, and the glide's continuation, read from painted
  // truth on BOTH sides (the painted extent before the snap, the painted
  // extent after the mutation), composes onto it and cancels it exactly.
  // Falsification: dropping that continuation leaves the FLIP standing,
  // so the drop frame reads 80 and the resize replays.
  testWidgets("a committed resize is continuous from the preview",
      (tester) async {
    final controller = _plain(tester, style: _previewStyle);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final drag = _resizeDrag(tester, controller);
    double painted() {
      return tester.getSize(find.byKey(_itemKey("m"))).width;
    }

    final edge = viewport.rectOfItem("m")!;
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, Offset(edge.right, edge.center.dy)),
        edge: BoardResizeEdges.trailing,
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, Offset(240.0, edge.center.dy)));
    await tester.pump();
    // A SETTLED preview: the painted extent is already the committed one.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 16));
    expect(painted(), closeTo(200.0, 0.01));

    drag.endDrag(cancel: false);
    await tester.pump();
    // TARGET: no step at the drop frame, and none after it.
    expect(controller.spanOf("m")!.colSpan, 5);
    expect(painted(), closeTo(200.0, 0.01));
    await tester.pump(const Duration(milliseconds: 100));
    expect(painted(), closeTo(200.0, 0.01));
    await tester.pumpAndSettle();
    expect(painted(), closeTo(200.0, 0.01));
  });

  // P3, the moving half: a release MID-preview finishes the remainder
  // rather than stepping, the drop-settle record carrying it.
  // Falsification: dropping the glide's continuation, or returning early
  // from it on a zero corner correction, steps the item at the drop.
  testWidgets("a resize committed mid-preview finishes from where it "
      "painted", (tester) async {
    final controller = _plain(tester, style: _previewStyle);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final drag = _resizeDrag(tester, controller);
    double painted() {
      return tester.getSize(find.byKey(_itemKey("m"))).width;
    }

    final edge = viewport.rectOfItem("m")!;
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, Offset(edge.right, edge.center.dy)),
        edge: BoardResizeEdges.trailing,
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, Offset(240.0, edge.center.dy)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: mid-preview, half way from 80 to 200.
    final held = painted();
    expect(held, closeTo(140.0, 1.0));

    drag.endDrag(cancel: false);
    await tester.pump();
    // TARGET: the drop frame keeps the painted width, and the remainder
    // runs on from there.
    expect(painted(), closeTo(held, 1.0));
    await tester.pumpAndSettle();
    expect(painted(), closeTo(200.0, 0.01));
  });

  // P4. A preview in MOTION lays out per tick, because the child's
  // constraints change; a SETTLED one does not, or every tick of every
  // other source would lay the board out for a constant number. The
  // second half needs another source TICKING to be observable at all,
  // the engine's own ticker having stopped at the settle, so a lead-only
  // slide on a second item runs beside it.
  // Falsification: putting a held extent in the layout-driving union
  // unconditionally makes that slide's every tick a layout.
  testWidgets("a resize preview lays out per tick while it moves and not "
      "once settled", (tester) async {
    final controller = _plain(tester, style: _previewStyle);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final drag = _resizeDrag(tester, controller);
    final edge = viewport.rectOfItem("m")!;
    drag.startDrag(
      key: "m",
      renderPort: viewport,
      pointerGlobal: _global(tester, Offset(edge.right, edge.center.dy)),
      edge: BoardResizeEdges.trailing,
    );
    drag.updateDrag(_global(tester, Offset(240.0, edge.center.dy)));
    await tester.pump();
    final moving = viewport.debugPerformLayoutCount;
    await tester.pump(const Duration(milliseconds: 100));
    // TARGET: laying out while it moves.
    expect(viewport.debugPerformLayoutCount, greaterThan(moving));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.getSize(find.byKey(_itemKey("m"))).width,
      closeTo(200.0, 0.01),
    );
    // A lead-only slide on ANOTHER item, so something ticks while the
    // preview stands settled.
    controller.addItem(
      const _Item("t"),
      const BoardSpan(rowStart: 0, colStart: 0),
    );
    controller.moveItem(
      "t",
      const BoardSpan(rowStart: 0, colStart: 3),
    );
    await tester.pump();
    final settled = viewport.debugPerformLayoutCount;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    // TARGET: the settled preview adds no layout, though a paint-only
    // slide is ticking beside it.
    expect(controller.anim.hasActiveOffsets, isTrue);
    expect(viewport.debugPerformLayoutCount, settled);
    expect(
      tester.getSize(find.byKey(_itemKey("m"))).width,
      closeTo(200.0, 0.01),
    );
    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
  });

  // T7. A purge before a record's FIRST tick leaves the render where
  // the install frame left it: no router mirror has latched, and with
  // every level false the purge's notify routes neither a layout nor a
  // paint. Reachable only when the install runs INSIDE a frame before
  // its layout, which a transient-phase frame callback produces (a
  // ticker started there takes the frame's timestamp and first ticks a
  // frame later, `scheduler/ticker.dart:204`).
  // Falsification: without the empty structural notification the child
  // keeps its install-frame width for as long as nothing else lays out.
  testWidgets("restyling itemSlide to zero before the first tick lands "
      "extents", (tester) async {
    final controller = _plain(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();

    SchedulerBinding.instance.scheduleFrameCallback((_) {
      controller.resizeItem(
        "m",
        const BoardSpan(rowStart: 2, colStart: 1, colSpan: 4),
      );
    });
    await tester.pump();
    // Setup sanity: the install ran inside the frame and its layout read
    // the record, so the child is at the OLD width with no tick yet.
    expect(tester.getSize(find.byKey(_itemKey("m"))).width, closeTo(80.0, 0.01));

    controller.animationStyle = BoardAnimationStyle.disabled;
    await tester.pump();
    // TARGET: the purge re-dirtied layout, so the child lands.
    expect(
      tester.getSize(find.byKey(_itemKey("m"))).width,
      closeTo(160.0, 0.01),
    );
    await tester.pumpAndSettle();
  });

  // T8. The window bound, not the geometry rule, is what keeps a
  // shrinking item BUILT: items are obtained by their STRUCTURAL span's
  // intersection with the widened track range, and after the write that
  // span no longer reaches the window.
  // Falsification: a bound folding the lead alone leaves the obtain
  // window at 450, the structural span 200 to 400 never reaches it, and
  // the item is not built at all.
  testWidgets("the window bound covers an animated trailing edge past "
      "the obtain window", (tester) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(30, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: _slideOnly,
    );
    addTearDown(controller.dispose);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 5, colSpan: 16),
    );
    final horizontal = ScrollController();
    addTearDown(horizontal.dispose);
    await tester.pumpWidget(_board(controller, horizontal: horizontal));
    await tester.pumpAndSettle();
    // Columns 5 to 21 of 40: content 200 to 840, 640 wide.
    expect(tester.getSize(find.byKey(_itemKey("m"))).width, 640.0);

    // The visible window becomes 700 to 980; the obtain window starts at
    // 450 with the default 250 cache extent.
    horizontal.jumpTo(700.0);
    await tester.pumpAndSettle();
    // Setup sanity: the item is still built, its span reaching past 700.
    expect(find.byKey(_itemKey("m")), findsOneWidget);

    // SHRINK to columns 5 to 10: content 200 to 400, which is past the
    // obtain window's leading edge.
    controller.resizeItem(
      "m",
      const BoardSpan(rowStart: 2, colStart: 5, colSpan: 5),
    );
    await tester.pump();
    // TARGET: still built, still painting its old width.
    expect(find.byKey(_itemKey("m")), findsOneWidget);
    expect(tester.getSize(find.byKey(_itemKey("m"))).width, closeTo(640.0, 0.01));
    await tester.pumpAndSettle();
  });

  // T5. `setItems` re-spans through the same path, which its own doc
  // already claims.
  // Falsification: a `setItems` that keeps writing the span directly
  // installs nothing and reports a zero delta.
  testWidgets("a setItems span change animates through the same path",
      (tester) async {
    final controller = _plain(tester);
    controller.setItems(const <BoardPlacement<_Item>>[
      BoardPlacement<_Item>(
        _Item("m"),
        BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
      ),
    ]);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final id = controller.idOfKey("m");

    controller.setItems(const <BoardPlacement<_Item>>[
      BoardPlacement<_Item>(
        _Item("m"),
        BoardSpan(rowStart: 2, colStart: 1, colSpan: 4),
      ),
    ]);
    // TARGET.
    expect(controller.anim.extentDeltaOf(id), const Offset(-80.0, 0.0));
    await tester.pumpAndSettle();
  });
}
