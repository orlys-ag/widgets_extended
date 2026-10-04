/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 5. These are the PRODUCTION arm of AC3,
/// against the real `RenderBoardViewport`; the mechanism was trialed first
/// on a probe subclass, and that probe stays at
/// `test/board/correction_trial_test.dart` as the trial's kept evidence.
///
/// The CONTROL arm, the same script with corrections suppressed,
/// deliberately stays in that probe on its `correctionsEnabled`
/// constructor flag: suppression needs a constructor flag and
/// `RenderBoardViewport` gets no corrections-disable seam.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

/// The caller payload. No case here puts an item on the board.
class _Item {
  const _Item(this.key);

  final String key;
}

/// Extent every unmeasured row track is assumed to have.
const double _estimate = 100.0;

/// Total row tracks.
const int _trackCount = 400;

const double _viewportWidth = 300.0;
const double _viewportHeight = 400.0;

/// The extent a row track ACTUALLY has, which layout discovers only when
/// it builds the cell.
///
/// Every fourth track is 80 taller than the estimate, so a pass that
/// measures a previously unmeasured region always produces a non-zero
/// correction. A uniform 100 here would make a corrected and an
/// uncorrected board identical and every assertion below vacuous.
double _trueExtentOf(int track) {
  if (track % 4 == 0) {
    return _estimate + 80.0;
  }
  return _estimate;
}

Key _cellKey(int row) {
  return ValueKey<String>("c$row");
}

class _Cell extends StatelessWidget {
  const _Cell({required this.height, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: _viewportWidth, height: height);
  }
}

/// A board with ONE column of 400 content-sized rows: the shape the
/// correction exists for, and the shape the kept trial probe models.
BoardController<String, _Item> _controller(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: LazyContentAxis(_trackCount, _estimate)),
    columns: BoardAxisConfig(axis: UniformAxis(1, _viewportWidth)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _board(
  BoardController<String, _Item> controller,
  ScrollController vertical,
) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: _viewportWidth,
          height: _viewportHeight,
          child: Board<String, _Item>(
            controller: controller,
            verticalDetails: ScrollableDetails.vertical(controller: vertical),
            cellBuilder: (context, cell) {
              return _Cell(
                key: _cellKey(cell.row),
                height: _trueExtentOf(cell.row),
              );
            },
          ),
        ),
      ),
    ),
  );
}

RenderBoardViewport<String> _renderViewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

/// The track nearest the top of the viewport that is mounted now and, by
/// construction, still mounted after a small upward scroll.
int _topmostMountedTrack(WidgetTester tester) {
  var best = -1;
  var bestY = double.infinity;
  for (var track = 0; track < _trackCount; track++) {
    final finder = find.byKey(_cellKey(track));
    if (!tester.any(finder)) {
      continue;
    }
    final y = tester.getTopLeft(finder).dy;
    if (y >= 0.0 && y < bestY) {
      bestY = y;
      best = track;
    }
  }
  return best;
}

/// Rejections that reach the pass ceiling on the first layout of the
/// ceiling board: with no content-sized axis every pass returns a zero
/// correction and calls `applyContentDimensions`, so each rejection is one
/// stagnant pass, and the call after the ceiling is accepted.
const int _ceilingRejections = 5;

/// A vertical controller whose position answers `false` from
/// `applyContentDimensions`, the contract's "lay out again" answer, for
/// the first [rejections] calls, and defers to the stock position after.
class _RejectingController extends ScrollController {
  _RejectingController({required this.rejections});

  /// Rejections still to answer.
  int rejections;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _RejectingPosition(
      owner: this,
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _RejectingPosition extends ScrollPositionWithSingleContext {
  _RejectingPosition({
    required this.owner,
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  final _RejectingController owner;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    // Records the extents as a stock position does, so a rejection only
    // asks for another pass and never leaves the dimensions unset.
    final accepted = super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent,
    );
    if (owner.rejections > 0) {
      owner.rejections -= 1;
      return false;
    }
    return accepted;
  }
}

/// Pumps a 300 x 300 board of 12 rows of 200 by 3 columns of 100, both
/// axes fixed, whose vertical position rejects [rejections] content
/// dimension calls, and takes the ceiling report its first layout makes.
///
/// The first layout's window ends at 550, the viewport plus the default
/// cache extent, so it builds rows 0 to 2 only.
Future<_RejectingController> _pumpCeilingBoard(
  WidgetTester tester, {
  int rejections = _ceilingRejections,
}) async {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(12, 200.0)),
    columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  final vertical = _RejectingController(rejections: rejections);
  addTearDown(vertical.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300.0,
            height: 300.0,
            child: Board<String, _Item>(
              controller: controller,
              verticalDetails: ScrollableDetails.vertical(controller: vertical),
              cellBuilder: (context, cell) {
                return Text("r${cell.row}c${cell.col}");
              },
            ),
          ),
        ),
      ),
    ),
  );
  expect(
    tester.takeException()?.toString(),
    contains("STAGNANT placement passes"),
    reason:
        "The first layout must reach the pass ceiling and report it, or "
        "the assertions after this one are about a layout that settled.",
  );
  return vertical;
}

void main() {
  const double scrollUpBy = 300.0;
  const double startOffset = 20000.0;

  // The direction the whole file was blind to: estimates LARGER than the
  // actuals. On frame 1 the obtain loop walks estimate offsets, sizing
  // then shrinks every walked track, a fresh board has no measured anchor
  // so the correction is zero, and a settle test that accepts a
  // geometry-changing pass leaves the newly revealed rows unbuilt with
  // nothing left to dirty layout. Demonstrated before the fix: 7 of 20
  // visible rows built, permanently.
  // Falsification: dropping the changed-geometry clause from the settle
  // condition rebuilds the defect exactly.
  testWidgets("the first layout under oversized estimates covers the whole "
      "visible window", (tester) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      // Estimate 100 against true cell height 20: five times oversized.
      rows: BoardAxisConfig(axis: LazyContentAxis(60, 100.0)),
      columns: BoardAxisConfig(axis: UniformAxis(1, _viewportWidth)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: _viewportWidth,
              height: 400.0,
              child: Board<String, _Item>(
                controller: controller,
                verticalDetails: ScrollableDetails.vertical(
                  controller: vertical,
                ),
                cellBuilder: (context, cell) {
                  return _Cell(key: _cellKey(cell.row), height: 20.0);
                },
              ),
            ),
          ),
        ),
      ),
    );
    // Every one of the 20 rows the 400-tall viewport shows at 20 per row
    // exists on the FIRST frame, with no extra pump.
    for (var row = 0; row < 20; row++) {
      expect(
        find.byKey(_cellKey(row)),
        findsOneWidget,
        reason: "row $row is inside the visible window on frame 1",
      );
    }
    // And the loop still terminated inside its ceiling.
    final viewport = _renderViewport(tester);
    expect(viewport.debugLastCorrectionPassCount, lessThan(5));
  });

  // AC3 in-layout correction, production arm.
  // Asserts: the anchor moved by exactly the scroll delta AND
  // debugCorrectionCount greater than zero.
  // Falsification: a markNeedsLayout-for-next-frame implementation fails the
  // anchor assertion; one that never corrects fails debugCorrectionCount > 0.
  testWidgets(
    "measuring a track above the anchor leaves the anchor's painted y unchanged",
    (tester) async {
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      final controller = _controller(tester);
      await tester.pumpWidget(_board(controller, vertical));

      vertical.jumpTo(startOffset);
      await tester.pumpAndSettle();

      final tracked = _topmostMountedTrack(tester);
      expect(
        tracked,
        isNot(-1),
        reason:
            "The script must have a mounted track inside the viewport "
            "to follow, or the invariant below is about nothing.",
      );
      final before = tester.getTopLeft(find.byKey(_cellKey(tracked))).dy;

      // Scrolling UP reveals tracks that have never been measured.
      // Measuring them is what moves everything after them, and holding
      // the anchor still through that is the whole of the correction.
      vertical.jumpTo(vertical.position.pixels - scrollUpBy);
      await tester.pumpAndSettle();

      final after = tester.getTopLeft(find.byKey(_cellKey(tracked))).dy;
      expect(
        after - before,
        closeTo(scrollUpBy, 0.01),
        reason:
            "The anchor must follow the finger and nothing else. A "
            "measurement of a track above it must not move it.",
      );
      expect(
        _renderViewport(tester).debugCorrectionCount,
        greaterThan(0),
        reason:
            "The board must actually have called correctBy. Without "
            "this, an implementation that never corrects and never "
            "measures would satisfy the assertion above.",
      );
    },
  );

  // AC3 in-layout correction, convergence half.
  // Asserts: debugLastCorrectionPassCount is a LAST-VALUE field, so the case
  // scripts a SWEEP of jumps, takes worst = math.max(worst, ...) across it,
  // and asserts worst >= 2 AND worst < 5. The >= 2 half is the setup sanity
  // assertion, without which the cap assertion holds vacuously on a viewport
  // that never corrects anything.
  // Falsification: an implementation that converges only at the five-pass
  // break fails worst < 5; one that never corrects fails worst >= 2.
  testWidgets("the same scroll settles in two passes and never reaches the "
      "ceiling", (tester) async {
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    final controller = _controller(tester);
    await tester.pumpWidget(_board(controller, vertical));

    // A sweep, not one jump: the counter reports whichever layout ran
    // LAST, which is 1 whenever the final layout of a pump needed no
    // correction, so a single read cannot surface a routine climb toward
    // the ceiling.
    var worst = 0;
    for (var offset = 20000.0; offset > 18000.0; offset -= 137.0) {
      vertical.jumpTo(offset);
      await tester.pumpAndSettle();
      worst = math.max(
        worst,
        _renderViewport(tester).debugLastCorrectionPassCount,
      );
    }

    expect(
      worst,
      greaterThanOrEqualTo(2),
      reason:
          "At least one jump in this script must actually need a "
          "correction. If every layout settled in one pass, the cap "
          "assertion below would hold vacuously on a viewport that never "
          "corrects anything.",
    );
    expect(
      worst,
      lessThan(5),
      reason:
          "A cap that is routinely hit is a convergence bug, not a "
          "slow path.",
    );
  });

  // A layout that reaches the stagnant-pass ceiling reports and finishes:
  // the child manager's pass closes and the cells it built stay mounted.
  // Falsification: throwing at the ceiling leaves `r0c0` unbuilt.
  testWidgets("a layout that reaches the pass ceiling reports it and keeps "
      "its cells", (tester) async {
    await _pumpCeilingBoard(tester);

    expect(
      find.text("r0c0"),
      findsOneWidget,
      reason:
          "The layout that reached the ceiling must still close its child "
          "manager's pass, or the cells it built are unreachable from the "
          "element tree.",
    );
  });

  // The layout after a ceiling layout starts a fresh child manager pass
  // and builds the rows it scrolls to.
  // Falsification: throwing at the ceiling fails this layout's
  // `_startLayout` assert.
  testWidgets("the layout after a ceiling layout runs clean", (tester) async {
    final vertical = await _pumpCeilingBoard(tester);

    expect(
      find.text("r6c0"),
      findsNothing,
      reason:
          "Row 6, at 1200 to 1400, must lie outside the first layout's "
          "window, or the target below does not show that only the next "
          "layout built it.",
    );
    vertical.jumpTo(1200.0);
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason:
          "A layout after the ceiling must start a fresh child manager "
          "pass; the ceiling layout must not leave its pass open.",
    );
    expect(
      find.text("r6c0"),
      findsOneWidget,
      reason:
          "The layout after the ceiling must build the rows it scrolled to.",
    );
  });
}
