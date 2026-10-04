/// Tests for item 5A of the board audit fixes: how an animation source
/// reconciles an install, a refusal, a restyle or a settle with motion
/// already in flight.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 5A", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Every TARGET was red on the tree item 4 left, or is a DESIGN PIN
/// whose red was shown by the mutation its comment names, with every
/// setup sanity assertion before it passing.
///
/// Clock cadence: a case installs, pumps once with no duration (the
/// install frame; a ticker's first tick reports elapsed zero), then pumps
/// durations.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/_track_resize_animator.dart';
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

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

const BoardAnimationSpec _ms200 = BoardAnimationSpec(
  duration: Duration(milliseconds: 200),
  curve: Curves.linear,
);

const BoardAnimationSpec _ms300 = BoardAnimationSpec(
  duration: Duration(milliseconds: 300),
  curve: Curves.linear,
);

const BoardAnimationSpec _ms600 = BoardAnimationSpec(
  duration: Duration(milliseconds: 600),
  curve: Curves.linear,
);

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

RenderBoardViewport<String> _viewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

Rect _probe(WidgetTester tester, String key) {
  return tester.getRect(find.byKey(_itemKey(key)));
}

/// Unmounts the board before the controller's own tear-down disposes it.
/// Tear-downs run last-registered first, so registering this AFTER the
/// controller's dispose makes it run BEFORE it; without it, a failing
/// body leaves the board subscribed and the dispose assert adds a second,
/// unrelated error to the report.
void _unmountFirst(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _board(
  BoardController<String, _Item> controller, {
  double width = 280.0,
  double height = 300.0,
  double cellHeight = 20.0,
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

/// Six 50px rows by seven 40px columns, no lane axis.
BoardController<String, _Item> _plain(
  WidgetTester tester,
  BoardAnimationStyle style,
) {
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

/// Rows content-sized and carrying the lanes.
BoardController<String, _Item> _contentLane(
  WidgetTester tester,
  BoardAnimationStyle style, {
  double laneExtent = 18.0,
  double lanePadding = 4.0,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(
      axis: LazyContentAxis(6, 80.0),
      laneExtent: laneExtent,
      lanePadding: lanePadding,
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

/// Three content-sized rows, cells only, for the floor cases.
BoardController<String, _Item> _cellsOnly(
  WidgetTester tester,
  BoardAnimationStyle style,
) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: LazyContentAxis(3, 100.0)),
    columns: BoardAxisConfig(axis: UniformAxis(3, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Row 0 holds `a` and `b` on lanes 0 and 1 (40px); `d` sits on row 2.
void _addTwoLaneRow(BoardController<String, _Item> controller) {
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
  );
  controller.addItem(
    const _Item("b"),
    const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
  );
  controller.addItem(
    const _Item("d"),
    const BoardSpan(rowStart: 2, colStart: 2, colSpan: 4),
  );
}

const BoardAnimationStyle _easeOutBackResize = BoardAnimationStyle(
  trackResize: BoardAnimationSpec(
    duration: Duration(milliseconds: 300),
    curve: Curves.easeOutBack,
  ),
  itemSlide: _zero,
);

void main() {
  // Test 1 (F1). The interpolated extent of a shrinking track under an
  // overshooting curve goes below zero on the tree item 4 left, and the
  // cell is laid out under a negative maximum.
  testWidgets("an overshooting trackResize curve never paints a negative "
      "track extent", (tester) async {
    final controller = _cellsOnly(tester, _easeOutBackResize);
    _unmountFirst(tester);
    var cellHeight = 300.0;
    Widget board() {
      return _board(
        controller,
        width: 120.0,
        height: 600.0,
        cellHeight: cellHeight,
      );
    }

    await tester.pumpWidget(board());
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    // Setup sanity: the first measurement landed with no animation.
    expect(viewport.rectOfCell(0, 0)!.height, 300.0);

    cellHeight = 4.0;
    await tester.pumpWidget(board());
    // Setup sanity: the shrink is animating, not landed.
    expect(controller.anim.hasActiveTrackResize, isTrue);
    var minHeight = double.infinity;
    for (var frame = 0; frame < 25; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      // TARGET: layout never received an invalid constraint ...
      expect(tester.takeException(), isNull, reason: "frame $frame");
      final height = viewport.rectOfCell(0, 0)!.height;
      if (height < minHeight) {
        minHeight = height;
      }
    }
    // ... the painted track never went negative, and the overshoot
    // reached the floor, which is zero and not the axis minimum.
    expect(minHeight, greaterThanOrEqualTo(0.0));
    expect(minHeight, 0.0);
    await tester.pumpAndSettle();
    expect(viewport.rectOfCell(0, 0)!.height, 4.0);
  });

  // Test 2 (the floor's scope). DESIGN PIN: a floor and not a clamp of
  // the eased value, so a growing track keeps the curve's overshoot.
  // Red under a mutation clamping the eased value to [0, 1].
  testWidgets("an overshooting trackResize curve keeps its overshoot on a "
      "growing track", (tester) async {
    final controller = _cellsOnly(tester, _easeOutBackResize);
    _unmountFirst(tester);
    var cellHeight = 20.0;
    Widget board() {
      return _board(
        controller,
        width: 120.0,
        height: 600.0,
        cellHeight: cellHeight,
      );
    }

    await tester.pumpWidget(board());
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    expect(viewport.rectOfCell(0, 0)!.height, 20.0);

    cellHeight = 300.0;
    await tester.pumpWidget(board());
    expect(controller.anim.hasActiveTrackResize, isTrue);
    var maxHeight = 0.0;
    for (var frame = 0; frame < 25; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final height = viewport.rectOfCell(0, 0)!.height;
      if (height > maxHeight) {
        maxHeight = height;
      }
    }
    expect(maxHeight, greaterThan(300.0));
    await tester.pumpAndSettle();
    expect(viewport.rectOfCell(0, 0)!.height, 300.0);
  });

  // Test 3 (F2). An enter ramp starting while its row is mid-resize: the
  // ramp's term must show at once, over the resize's decaying residual,
  // and the row must never step.
  testWidgets("an enter ramp that starts while its track is mid-resize "
      "grows the row with it", (tester) async {
    final controller = _contentLane(
      tester,
      // The DEFAULT style: every family 300ms linear.
      const BoardAnimationStyle(),
      laneExtent: 40.0,
      lanePadding: 0.0,
    );
    _unmountFirst(tester);
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 0, colStart: 0, colSpan: 3),
    );
    await tester.pumpWidget(_board(controller, height: 400.0));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    // Setup sanity: row 0 holds a's lane, row 2 is cells only.
    expect(viewport.rectOfCell(0, 0)!.height, 40.0);
    expect(viewport.rectOfCell(2, 0)!.height, 20.0);

    // A cross-track move: row 2 grows 20 to 40 by an ordinary
    // trackResize.
    controller.moveItem(
      "a",
      const BoardSpan(rowStart: 2, colStart: 0, colSpan: 3),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: the resize is in flight, a third of the way.
    expect(controller.anim.hasActiveTrackResize, isTrue);
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(26.7, 0.5));

    // b overlaps a, so it takes lane 1 and ENTERS on the ramp. The frame
    // it arrives in is measured too: a hand-in at the ramp's first pass
    // would step the row there.
    var previous = viewport.rectOfCell(2, 0)!.height;
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 3),
    );
    await tester.pump();
    // Setup sanity: b is laned on lane 1 and entering.
    expect(controller.laneOf("b"), 1);
    expect(controller.anim.isEnteringItem(controller.idOfKey("b")), isTrue);

    var maxStep = (viewport.rectOfCell(2, 0)!.height - previous).abs();
    previous = viewport.rectOfCell(2, 0)!.height;
    var previousOverflow =
        viewport.rectOfItem("b")!.bottom - viewport.rectOfCell(2, 0)!.bottom;
    var overflowGrew = 0.0;
    for (var frame = 0; frame < 25; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final row = viewport.rectOfCell(2, 0)!;
      final step = (row.height - previous).abs();
      if (step > maxStep) {
        maxStep = step;
      }
      previous = row.height;
      final overflow = viewport.rectOfItem("b")!.bottom - row.bottom;
      if (overflow - previousOverflow > overflowGrew) {
        overflowGrew = overflow - previousOverflow;
      }
      previousOverflow = overflow;
    }
    // TARGET: the row moves continuously (a legitimate frame here moves
    // 40px / 300ms * 16ms for the ramp plus 20px / 300ms * 16ms for the
    // residual, 3.2px) ...
    expect(maxStep, lessThan(4.0));
    // ... and b never overflows its row by more than it did the frame
    // before: the row holds the ramp as it grows, and only the residual
    // the resize already had is left, shrinking.
    expect(overflowGrew, lessThan(0.01));
    await tester.pumpAndSettle();
    final row = viewport.rectOfCell(2, 0)!;
    expect(row.height, 80.0);
    expect(viewport.rectOfItem("b")!.bottom, row.bottom);
  });

  // Test 4 (F3). A measurement a zero trackResize refuses, recorded over
  // a makeRoom-family hand-off still in flight: the change lands this
  // frame, and the hand-off keeps running from the new extent.
  testWidgets("a measurement a zero trackResize refuses lands its change "
      "over an in-flight hand-off, which keeps running", (tester) async {
    final controller = _contentLane(
      tester,
      const BoardAnimationStyle(trackResize: _zero, itemSlide: _ms200),
    );
    _unmountFirst(tester);
    // Row 2 holds a, b, c on lanes 0, 1, 2 (58px); row 0 holds f (22px).
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
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    expect(viewport.rectOfCell(0, 0)!.height, 22.0);
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(
        onItemMoved: (key, span) {
          controller.moveItem(key, span);
        },
        autoScrollEdgeZone: 0.0,
      ),
    );
    addTearDown(drag.dispose);
    final liftB = viewport.rectOfItem("b")!.center;
    expect(
      drag.startDrag(
        key: "b",
        renderPort: viewport,
        pointerGlobal: _global(tester, liftB),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, Offset(liftB.dx, 11.0)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: the slot has grown row 0 half a lane.
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(31.0, 0.5));
    drag.endDrag(cancel: false);
    await tester.pump();
    // Setup sanity: b landed on row 0, and row 0's residue is continuing
    // on the hand-off's makeRoom-family resize, trackResize being off.
    expect(controller.spanOf("b")!.rowStart, 0);
    expect(controller.anim.hasActiveTrackResize, isTrue);
    final before = viewport.rectOfCell(0, 0)!.height;
    expect(before, closeTo(31.0, 0.5));

    // A third chip on row 0, lane 2: the cluster term grows one lane
    // (18px). No enter ramp (itemEnterExit inherits the zero
    // trackResize), so this is an ordinary-arm measurement, which the
    // zero trackResize refuses to animate.
    controller.addItem(
      const _Item("e"),
      const BoardSpan(rowStart: 0, colStart: 1, colSpan: 3),
    );
    await tester.pump();
    expect(controller.laneOf("e"), 2);
    // TARGET: the refused change lands this frame, whole ...
    expect(viewport.rectOfCell(0, 0)!.height - before, closeTo(18.0, 0.5));
    // ... and the hand-off is still running (DESIGN PIN: red under a
    // refusal that drops the track's state).
    expect(controller.anim.hasActiveTrackResize, isTrue);
    var previous = viewport.rectOfCell(0, 0)!.height;
    var maxStep = 0.0;
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final height = viewport.rectOfCell(0, 0)!.height;
      final step = (height - previous).abs();
      if (step > maxStep) {
        maxStep = step;
      }
      previous = height;
    }
    // TARGET: no frame steps; the residual (9px over the hand-off's
    // remaining 100ms) moves 1.5px a frame.
    expect(maxStep, lessThan(2.0));
    await tester.pumpAndSettle();
    final row = viewport.rectOfCell(0, 0)!;
    expect(row.height, 58.0);
    expect(viewport.rectOfItem("e")!.bottom, lessThanOrEqualTo(row.bottom));
  });

  // Test 5 (A). REPLACES make_room_track_sizing_test.dart's "a gap
  // opening on a resizing row hands that resize in rather than painting
  // behind it", whose premise was the absolute storage: that a state in
  // flight hides every recorded term. A residual state shows the term at
  // once and keeps decaying under it, so the gap needs no hand-in, and
  // the hand-in's own cost, a pop by the whole residual, goes with it.
  testWidgets("a gap opening on a resizing row continues that resize "
      "under the term", (tester) async {
    final controller = _contentLane(
      tester,
      const BoardAnimationStyle(trackResize: _ms600, itemSlide: _ms300),
    );
    _unmountFirst(tester);
    _addTwoLaneRow(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    expect(viewport.rectOfCell(0, 0)!.height, 40.0);
    // A resize from 76 painted down to the 40 the axis stores, on the
    // internal-use channel rather than raced for.
    controller.animateTrackResize(Axis.vertical, 0, 76.0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: a sixth of the way, 36 * 5 / 6 above the stored 40.
    expect(controller.anim.hasActiveTrackResize, isTrue);
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(70.0, 0.5));
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
      lifted: true,
    );
    await tester.pump();
    // TARGET: the gap's first frame paints what the frame before did
    // (the term is 40 at clock 0, the residual 30) ...
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(70.0, 0.5));
    // ... the resize is still in flight ...
    expect(controller.anim.hasActiveTrackResize, isTrue);
    await tester.pump(const Duration(milliseconds: 150));
    // ... and the row is the term plus the decaying residual: 49 plus
    // 36 * (1 - 250 / 600). Ignoring the term paints 61.
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(70.0, 0.5));
    await tester.pump(const Duration(milliseconds: 150));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(70.0, 0.5));
    // The resize ends at 600ms: the row is the term alone.
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.anim.hasActiveTrackResize, isFalse);
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(58.0, 0.5));
    controller.releaseMakeRoomPreview();
    await tester.pumpAndSettle();
    expect(viewport.rectOfCell(0, 0)!.height, 40.0);
  });

  // Test 6 (round 1's rule). An install whose residual is within the
  // tolerance is no motion, and drops the state the track holds: kept, it
  // would add its residual over an extent that already arrived. Reached
  // through the animator, as track_resize_test.dart does, because the
  // board reaches it only where a new settled extent lands within the
  // tolerance of what paints, which no drag can be timed to hit.
  // Red under a mutation that removes the drop.
  testWidgets("an install whose residual is within tolerance drops the "
      "standing state", (tester) async {
    var settled = 40.0;
    final animator = TrackResizeAnimator(
      vsync: tester,
      styleOf: () {
        return const BoardAnimationStyle(trackResize: _ms600);
      },
      settledExtentOf: (axis, track) {
        return settled;
      },
      onTick: () {},
    );
    addTearDown(animator.dispose);
    animator.animateTrackResize(Axis.vertical, 1, 76.0);
    // Setup sanity: a residual of 36 over the settled 40, at clock 0.
    expect(animator.hasActive, isTrue);
    expect(animator.animatedExtentOf(Axis.vertical, 1), 76.0);

    // The axis records exactly what paints, and the sizing step installs
    // from there.
    settled = 76.0;
    animator.animateTrackResize(Axis.vertical, 1, 76.0);
    // TARGET: nothing stands, and the track paints its settled extent.
    expect(animator.hasActive, isFalse);
    expect(animator.animatedExtentOf(Axis.vertical, 1), 76.0);
  });

  // Test 7 (F4 contract). A refused slide install creates no motion and
  // destroys none. DESIGN PINS: red under a refusal that drops the
  // record (the left lands at once) and under one that restarts the
  // record's clock (a quarter of the way at +50ms, not three quarters).
  testWidgets("a zero-duration moveItem mid-slide moves by the change and "
      "keeps the slide running", (tester) async {
    final controller = _plain(
      tester,
      const BoardAnimationStyle(
        trackResize: _zero,
        itemSlide: _ms200,
        itemEnterExit: _zero,
      ),
    );
    _unmountFirst(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller, cellHeight: 50.0));
    await tester.pumpAndSettle();
    controller.moveItem(
      "m",
      const BoardSpan(rowStart: 2, colStart: 4, colSpan: 2),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: half way from column 1 (40) to column 4 (160), on
    // row 2 (100).
    expect(_probe(tester, "m").left, closeTo(100.0, 0.5));
    expect(_probe(tester, "m").top, 100.0);

    controller.moveItem(
      "m",
      const BoardSpan(rowStart: 4, colStart: 4, colSpan: 2),
      duration: Duration.zero,
    );
    await tester.pump();
    // TARGET: the change lands whole this frame ...
    expect(_probe(tester, "m").top, 200.0);
    // ... and the slide in flight keeps its residual ...
    expect(_probe(tester, "m").left, closeTo(100.0, 0.5));
    await tester.pump(const Duration(milliseconds: 50));
    // ... on its own clock: three quarters of the way at 150ms.
    expect(_probe(tester, "m").left, closeTo(130.0, 0.5));
    await tester.pumpAndSettle();
    expect(_probe(tester, "m").topLeft, const Offset(160.0, 200.0));
  });

  group("restyling a family to zero stops that family's motion only", () {
    // Test 8a (F6). The style doc says a dropSettle glide runs on when
    // itemSlide is zeroed; the setter purged it.
    testWidgets("restyling itemSlide to zero leaves an explicitly-on "
        "dropSettle glide running", (tester) async {
      const style = BoardAnimationStyle(
        trackResize: _zero,
        itemSlide: _ms200,
        itemEnterExit: _zero,
        dropSettle: BoardAnimationSpec(
          duration: Duration(milliseconds: 400),
          curve: Curves.linear,
        ),
      );
      final controller = _plain(tester, style);
      _unmountFirst(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
      );
      await tester.pumpWidget(_board(controller, cellHeight: 50.0));
      await tester.pumpAndSettle();
      final id = controller.idOfKey("m");
      controller.animateDropSettle(
        "m",
        const Offset(0.0, 40.0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.linear,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Setup sanity: a quarter of the way through the glide.
      expect(controller.anim.offsetOfItem(id).dy, closeTo(30.0, 0.5));

      controller.animationStyle = style.copyWith(itemSlide: _zero);
      // Setup sanity: dropSettle is explicitly on after the restyle.
      expect(
        controller.animationStyle.effectiveDropSettle.duration,
        const Duration(milliseconds: 400),
      );
      // TARGET: the glide still runs.
      expect(controller.anim.offsetOfItem(id).dy, closeTo(30.0, 0.5));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.anim.offsetOfItem(id).dy, closeTo(20.0, 0.5));
      await tester.pumpAndSettle();
    });

    // Test 8b. DESIGN PIN: the scope is the RESOLVED family, so a glide
    // whose dropSettle inherits itemSlide stops with it. Red under a
    // setter that purges only itemSlide-family records.
    testWidgets("restyling itemSlide to zero stops a glide that inherits "
        "it", (tester) async {
      const style = BoardAnimationStyle(
        trackResize: _zero,
        itemSlide: _ms200,
        itemEnterExit: _zero,
      );
      final controller = _plain(tester, style);
      _unmountFirst(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
      );
      await tester.pumpWidget(_board(controller, cellHeight: 50.0));
      await tester.pumpAndSettle();
      final id = controller.idOfKey("m");
      controller.animateDropSettle(
        "m",
        const Offset(0.0, 40.0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.linear,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.anim.offsetOfItem(id).dy, closeTo(30.0, 0.5));

      controller.animationStyle = style.copyWith(itemSlide: _zero);
      // Stopped in the setter, before any tick could reach the zero
      // guard.
      expect(controller.anim.offsetOfItem(id), Offset.zero);
      expect(controller.anim.hasActiveOffsets, isFalse);
    });

    // Test 9a (C, tracks). trackResize to zero FINALIZED every state,
    // including a makeRoom-family hand-off whose family is still on.
    testWidgets("restyling trackResize to zero leaves a makeRoom-family "
        "resize running", (tester) async {
      const style = BoardAnimationStyle(
        trackResize: _ms300,
        itemSlide: _ms300,
        makeRoom: _ms600,
      );
      final controller = _contentLane(tester, style);
      _unmountFirst(tester);
      _addTwoLaneRow(controller);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      final viewport = _viewport(tester);
      expect(viewport.rectOfCell(0, 0)!.height, 40.0);
      controller.animateTrackResize(
        Axis.vertical,
        0,
        76.0,
        family: BoardAnimationFamily.makeRoom,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(viewport.rectOfCell(0, 0)!.height, closeTo(70.0, 0.5));

      controller.animationStyle = style.copyWith(trackResize: _zero);
      // TARGET: the makeRoom-family resize is still in flight ...
      expect(controller.anim.hasActiveTrackResize, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      // ... and still moving on its own clock.
      expect(viewport.rectOfCell(0, 0)!.height, closeTo(64.0, 0.5));
      await tester.pumpAndSettle();
    });

    // Test 9b. makeRoom to zero stops a makeRoom-family resize in the
    // setter, synchronously, rather than on the next tick.
    testWidgets("restyling makeRoom to zero stops a makeRoom-family resize "
        "at once", (tester) async {
      const style = BoardAnimationStyle(
        trackResize: _ms300,
        itemSlide: _ms300,
        makeRoom: _ms600,
      );
      final controller = _contentLane(tester, style);
      _unmountFirst(tester);
      _addTwoLaneRow(controller);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      final viewport = _viewport(tester);
      controller.animateTrackResize(
        Axis.vertical,
        0,
        76.0,
        family: BoardAnimationFamily.makeRoom,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(viewport.rectOfCell(0, 0)!.height, closeTo(70.0, 0.5));

      controller.animationStyle = style.copyWith(makeRoom: _zero);
      // TARGET: stopped in the setter, before any tick could reach the
      // zero guard ...
      expect(controller.anim.hasActiveTrackResize, isFalse);
      // ... landing at the extent the axis stores.
      expect(controller.anim.animatedExtentOf(Axis.vertical, 0), 40.0);
    });
  });
}
