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
import 'package:widgets_extended/board/_board_animation_coordinator.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key, [this.height = 20.0]);

  final String key;

  /// Cells covered by this item size themselves to it, which is what
  /// makes an updateItem a re-measurement trigger.
  final double height;
}

const BoardAnimationSpec _ms300 = BoardAnimationSpec(
  duration: Duration(milliseconds: 300),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

/// Resizes animate; enters, exits and slides are off.
const BoardAnimationStyle _resizeOnly = BoardAnimationStyle(
  trackResize: _ms300,
  itemSlide: _zero,
  itemEnterExit: _zero,
);

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  int rows = 6,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(
      axis: LazyContentAxis(rows, 80.0),
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
  return controller;
}

Widget _board(
  BoardController<String, _Item> controller, {
  ScrollController? vertical,
  double height = 400.0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280.0,
          height: height,
          child: Board<String, _Item>(
            controller: controller,
            verticalDetails: vertical == null
                ? const ScrollableDetails.vertical()
                : ScrollableDetails.vertical(controller: vertical),
            cellBuilder: (context, cell) {
              var cellHeight = 20.0;
              for (final key in controller.itemsAt(cell.row, cell.col)) {
                final item = controller.itemOf(key);
                if (item != null && item.height > cellHeight) {
                  cellHeight = item.height;
                }
              }
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

RenderBoardViewport<String> _viewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

BoardSpan _chip(int row, int colStart, int colSpan) {
  return BoardSpan(rowStart: row, colStart: colStart, colSpan: colSpan);
}

void main() {
  // Performance plan T4 (plans/2026-09-07-board-performance-plan.md).
  // Asserts: a layout under in-flight resizes on every visible row reads
  // the resize animator's shift walk once per distinct track per
  // invalidation window, not twice per positioned cell.
  // Falsification: the per-cell reads at the positioning sweep report at
  // least two per cell, 800 for the 400 visible cells.
  testWidgets(
    "a layout under in-flight resizes reads the animator once per track",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: LazyContentAxis(20, 20.0)),
        columns: BoardAxisConfig(axis: UniformAxis(20, 14.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      var cellHeight = 20.0;
      // A fresh closure per call: pumping the tree again replaces the
      // delegate, which rebuilds and re-measures every cell without an
      // item, and a content-sized axis without a lane extent admits none.
      Widget board() {
        return MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 280.0,
                height: 400.0,
                child: Board<String, _Item>(
                  controller: controller,
                  cellBuilder: (context, cell) {
                    return SizedBox(width: 14.0, height: cellHeight);
                  },
                ),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(board());
      final viewport = _viewport(tester);
      // Setup sanity: the whole 20 by 20 lattice is visible.
      expect(viewport.rectOfCell(19, 19), isNotNull);
      controller.animationStyle = _resizeOnly;
      // Every row re-measures taller on the rebuild, so every visible row
      // installs a resize on the same frame.
      cellHeight = 30.0;
      await tester.pumpWidget(board());
      final coordinator = controller.anim as BoardAnimationCoordinator<String>;
      expect(controller.anim.hasActiveTrackResize, isTrue);
      coordinator.trackResize.debugShiftCallCount = 0;
      final layoutsBefore = viewport.debugPerformLayoutCount;

      await tester.pump(const Duration(milliseconds: 16));

      expect(viewport.debugPerformLayoutCount, layoutsBefore + 1);
      expect(viewport.debugLastCorrectionPassCount, 1);
      expect(coordinator.trackResize.debugShiftCallCount, lessThan(200));
      // Let the resizes finish so no ticker outlives the test.
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  // AC14 reflow without slides.
  // Asserts: debugSlideInstallCount is unchanged across the resize while
  // every following item's painted rect moves. The style keeps itemSlide
  // LIVE: under a zero itemSlide the kill switch refuses any injected
  // install before the counter sees it, which made an earlier version of
  // this fixture unable to fail against the very defect it names.
  // Falsification: an implementation that installs one slide per item
  // fails here while passing visually.
  testWidgets(
    "a trackResize reflows every following item with zero slide installs",
    (tester) async {
      final controller = _controller(tester);
      controller.addItem(const _Item("h"), _chip(0, 0, 2));
      controller.addItem(const _Item("m1"), _chip(2, 0, 2));
      controller.addItem(const _Item("m2"), _chip(4, 0, 2));
      await tester.pumpWidget(_board(controller));
      controller.animationStyle = const BoardAnimationStyle(
        trackResize: _ms300,
        itemSlide: _ms300,
        itemEnterExit: _zero,
      );
      final viewport = _viewport(tester);
      final installsBefore = viewport.debugSlideInstallCount;

      controller.updateItem("h", const _Item("h", 60.0));
      await tester.pump();
      var lastTop1 = tester.getRect(find.byKey(_itemKey("m1"))).top;
      var lastTop2 = tester.getRect(find.byKey(_itemKey("m2"))).top;
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        final top1 = tester.getRect(find.byKey(_itemKey("m1"))).top;
        final top2 = tester.getRect(find.byKey(_itemKey("m2"))).top;
        expect(top1, greaterThan(lastTop1));
        expect(top2, greaterThan(lastTop2));
        lastTop1 = top1;
        lastTop2 = top2;
      }
      expect(viewport.debugSlideInstallCount, installsBefore);
      await tester.pumpAndSettle();
    },
  );

  // DERIVED name. No AC; the install site and the correction anchor,
  // neither of which AC14 can see.
  // Asserts: an already measured track re-measured larger by an
  // updateItem, NOT by an enter, with the resized track INSIDE the
  // window: debugCorrectionCount is unchanged across every tick of the
  // resize while the following item's painted rect moves on each one,
  // which is what the SETTLED anchor buys.
  // Falsification: an anchor reading animatedExtentOf emits a correctBy
  // per tick and fails it.
  testWidgets("a re-measured track inside the window reflows with no "
      "correction", (tester) async {
    final controller = _controller(tester);
    controller.addItem(const _Item("h"), _chip(0, 0, 2));
    controller.addItem(const _Item("m"), _chip(2, 0, 2));
    await tester.pumpWidget(_board(controller));
    controller.animationStyle = _resizeOnly;
    final viewport = _viewport(tester);

    controller.updateItem("h", const _Item("h", 60.0));
    await tester.pump();
    final correctionsAtInstall = viewport.debugCorrectionCount;
    var lastTop = tester.getRect(find.byKey(_itemKey("m"))).top;
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      final top = tester.getRect(find.byKey(_itemKey("m"))).top;
      expect(top, greaterThan(lastTop));
      lastTop = top;
      expect(viewport.debugCorrectionCount, correctionsAtInstall);
    }
    await tester.pumpAndSettle();
    expect(viewport.debugCorrectionCount, correctionsAtInstall);
  });

  // DERIVED name. No AC; the same install site with the resized track
  // BEFORE the window: the animated accumulation anchors at the window's
  // first track, so the ramp is invisible there and the anchor holds.
  // Asserts: the anchor's painted y is unchanged across the whole resize.
  testWidgets("a re-measured track before the window leaves the anchor's "
      "painted y unchanged", (tester) async {
    final controller = _controller(tester, rows: 60);
    controller.addItem(const _Item("h"), _chip(0, 0, 2));
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await tester.pumpWidget(
      _board(controller, vertical: vertical, height: 200.0),
    );
    await tester.pumpAndSettle();
    controller.animationStyle = _resizeOnly;
    final viewport = _viewport(tester);

    controller.updateItem("h", const _Item("h", 60.0));
    await tester.pump();
    vertical.jumpTo(500.0);
    await tester.pump();
    final anchored = viewport.rectOfCell(30, 0)!.top;
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      expect(viewport.rectOfCell(30, 0)!.top, anchored);
    }
    await tester.pumpAndSettle();
    expect(viewport.rectOfCell(30, 0)!.top, anchored);
  });

  // DERIVED name. No AC.
  // Asserts: controller.anim.hasActiveTrackResize is false on the frame a
  // first measurement lands, read through the existing reader rather than
  // through a new seam.
  // Falsification: this is what separates the first-measurement arm from
  // the re-measurement arm and what stops every scroll into new
  // territory from rippling.
  testWidgets(
    "a first measurement of a previously unmeasured track installs "
    "nothing",
    (tester) async {
      final controller = _controller(tester, rows: 60);
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        _board(controller, vertical: vertical, height: 200.0),
      );
      await tester.pumpAndSettle();
      controller.animationStyle = _resizeOnly;

      // Far into never-measured territory: estimates 80, cells 20.
      vertical.jumpTo(700.0);
      await tester.pump();
      expect(controller.anim.hasActiveTrackResize, isFalse);
      await tester.pumpAndSettle();
      expect(controller.anim.hasActiveTrackResize, isFalse);
    },
  );

  // DERIVED name. No AC; the THIRD case, which pins the enter carve-out
  // AND the ramp hand-off, one mechanism that cannot be pinned apart.
  // Asserts: hasActiveTrackResize is false on every frame of the enter
  // AND on the settle frame and after it, while the track's rectOfCell
  // extent grows monotonically to its settled value, and
  // debugPerformLayoutCount stops advancing once the enter settles.
  // Falsification: without the carve-out the flag reports true and
  // layout stays dirty for a resize duration after the settle; with the
  // carve-out but without the hand-off, a real resize is installed for
  // the ramp's last tick, so the flag is true on the settle frame while
  // the extent is still monotonic. Neither half alone separates the two.
  testWidgets(
    "an addItem into an already-measured content-sized track installs no "
    "trackResize",
    (tester) async {
      final controller = _controller(tester);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      controller.animationStyle = const BoardAnimationStyle(
        trackResize: _ms300,
        itemSlide: _zero,
        itemEnterExit: _ms300,
      );
      final viewport = _viewport(tester);

      controller.addItem(const _Item("n"), _chip(0, 0, 2));
      await tester.pump();
      var lastExtent = viewport.rectOfCell(0, 0)!.height;
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 55));
        expect(controller.anim.hasActiveTrackResize, isFalse);
        final extent = viewport.rectOfCell(0, 0)!.height;
        expect(extent, greaterThanOrEqualTo(lastExtent));
        lastExtent = extent;
      }
      // Settled: the cluster term, one lane of 18 plus the padding, atop
      // the 20px cells.
      expect(viewport.rectOfCell(0, 0)!.height, 22.0);
      expect(controller.anim.hasActiveTrackResize, isFalse);
      await tester.pumpAndSettle();
      final layoutsAfterSettle = viewport.debugPerformLayoutCount;
      await tester.pump(const Duration(milliseconds: 100));
      expect(viewport.debugPerformLayoutCount, layoutsAfterSettle);
    },
  );

  // DERIVED name. No AC; the FOURTH case, the hand-off's off-window
  // form, which the third cannot reach.
  // Asserts: scroll the track out of the window mid-enter, let the enter
  // settle off-window, scroll back, and assert rectOfCell's extent is
  // the settled one on the first frame it is visible and
  // hasActiveTrackResize is false.
  // Falsification: a hand-off that installs instead of recording
  // animates the residue into view, which the first assertion fails.
  testWidgets(
    "an addItem into an off-window measured track is visible at its "
    "settled extent",
    (tester) async {
      final controller = _controller(tester, rows: 60);
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        _board(controller, vertical: vertical, height: 200.0),
      );
      await tester.pumpAndSettle();
      controller.animationStyle = const BoardAnimationStyle(
        trackResize: _ms300,
        itemSlide: _zero,
        itemEnterExit: _ms300,
      );
      final viewport = _viewport(tester);

      controller.addItem(const _Item("n"), _chip(0, 0, 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      vertical.jumpTo(600.0);
      await tester.pumpAndSettle();

      vertical.jumpTo(0.0);
      await tester.pump();
      expect(viewport.rectOfCell(0, 0)!.height, 22.0);
      expect(controller.anim.hasActiveTrackResize, isFalse);
    },
  );

  // DERIVED name. No AC; the trackResize half of the prior-tick latch,
  // the same shape as the enter case in item_enter_exit_test.dart.
  // Asserts: on a content-sized track that shrinks with nothing else in
  // flight, the track's painted extent reaches its settled value rather
  // than stopping a tick short.
  // Falsification: against a routing with no prior-tick mirror the
  // extent stops a tick short.
  testWidgets(
    "a shrinking content-sized track with nothing else in flight reaches "
    "its settled extent",
    (tester) async {
      final controller = _controller(tester);
      controller.addItem(const _Item("h", 60.0), _chip(0, 0, 2));
      await tester.pumpWidget(_board(controller));
      controller.animationStyle = _resizeOnly;
      final viewport = _viewport(tester);
      // Setup sanity: the tall payload holds the track at 60.
      expect(viewport.rectOfCell(0, 0)!.height, 60.0);

      controller.updateItem("h", const _Item("h", 20.0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      // Setup sanity: mid-shrink.
      final mid = viewport.rectOfCell(0, 0)!.height;
      expect(mid, lessThan(60.0));
      expect(mid, greaterThan(22.0));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      // The settled value exactly: cells 20 under a one-lane cluster of
      // 18 plus 4.
      expect(viewport.rectOfCell(0, 0)!.height, 22.0);
      expect(controller.anim.hasActiveTrackResize, isFalse);
    },
  );
}
