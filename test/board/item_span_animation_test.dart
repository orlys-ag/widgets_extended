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
import 'package:widgets_extended/board/board_controller.dart';
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
              return const SizedBox(width: 40.0, height: 50.0);
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
