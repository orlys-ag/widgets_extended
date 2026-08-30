/// TRIAL for section 7.3 of
/// `plans/2026-08-29-board-view-requirements.md`.
///
/// THE QUESTION. A `LazyContentAxis` discovers a track's real extent only
/// when that track is laid out. When a track BEFORE the anchor is measured
/// and turns out to differ from the estimate, every offset after it shifts,
/// so the content under the viewport moves even though the user did not
/// scroll it. The fix is a scroll correction. In sliver-land a sliver
/// returns `SliverGeometry.scrollOffsetCorrection` and the viewport aborts
/// and re-runs layout. `RenderTwoDimensionalViewport` has no such protocol:
/// `performLayout` calls `layoutChildSequence()` exactly once
/// (`widgets/two_dimensional_viewport.dart:1329-1336`) and the file contains
/// no `correctBy` at all.
///
/// The requirements document proposes running the loop ourselves, inside
/// `layoutChildSequence`: measure, detect a correction, call
/// `ViewportOffset.correctBy`, and re-run the placement pass within the same
/// framework call. `correctBy` is documented as a layout-time correction
/// that changes `pixels` without notifying listeners
/// (`rendering/viewport_offset.dart:188-200`), and `ScrollPosition`
/// implements it as `_pixels += correction` plus a flag
/// (`widgets/scroll_position.dart:458-465`), which is what makes that look
/// legal. Reasoning is not evidence, so this file is the evidence.
///
/// WHAT IT ASSERTS. The invariant a correction exists to protect: when the
/// user scrolls by D, the content moves by exactly D. Nothing else moves it.
/// The discriminating pair is the same scroll script run against a viewport
/// with corrections on and with corrections off; the uncorrected run must
/// FAIL the invariant, or the corrected run proves nothing.
///
/// The subclass here is a probe, not a draft of `RenderBoardViewport`. It
/// models one column of vertically stacked tracks with a deliberately
/// simple O(n) axis, because the question is about the correction protocol,
/// not about the Fenwick tree of section 4.4.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Extent every unmeasured track is assumed to have.
const double kEstimate = 100.0;

/// Total tracks on the vertical axis.
const int kTrackCount = 400;

/// Viewport geometry for every test here.
const double kViewportWidth = 300.0;
const double kViewportHeight = 400.0;

/// The extent a track ACTUALLY has, discovered only when it is laid out.
///
/// Every fourth track is 80px taller than the estimate, so a pass that
/// measures a previously unmeasured region always produces a non-zero
/// correction. A uniform 100.0 here would make the corrected and
/// uncorrected runs identical and the trial vacuous.
double trueExtentOf(int track) {
  if (track % 4 == 0) {
    return kEstimate + 80.0;
  }
  return kEstimate;
}

/// Minimal stand-in for `LazyContentAxis`: unmeasured tracks report the
/// estimate, measured tracks report what layout found, and measurements
/// persist across layouts.
class LazyTrackAxis {
  final Map<int, double> _measured = <int, double>{};

  bool isMeasured(int track) {
    return _measured.containsKey(track);
  }

  double extentOf(int track) {
    return _measured[track] ?? kEstimate;
  }

  void record(int track, double extent) {
    _measured[track] = extent;
  }

  double offsetOf(int track) {
    var sum = 0.0;
    for (var i = 0; i < track; i++) {
      sum += extentOf(i);
    }
    return sum;
  }

  int trackAt(double offset) {
    var acc = 0.0;
    for (var i = 0; i < kTrackCount; i++) {
      final next = acc + extentOf(i);
      if (offset < next) {
        return i;
      }
      acc = next;
    }
    return kTrackCount - 1;
  }

  double get totalExtent {
    return offsetOf(kTrackCount);
  }
}

// ---------------------------------------------------------------------------
// The probe render object
// ---------------------------------------------------------------------------

class TrialViewport extends TwoDimensionalViewport {
  const TrialViewport({
    super.key,
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required TwoDimensionalChildBuilderDelegate delegate,
    required super.mainAxis,
    required this.axis,
    required this.correctionsEnabled,
  }) : super(delegate: delegate);

  final LazyTrackAxis axis;
  final bool correctionsEnabled;

  @override
  RenderTrialViewport createRenderObject(BuildContext context) {
    return RenderTrialViewport(
      horizontalOffset: horizontalOffset,
      horizontalAxisDirection: horizontalDetailsDirection,
      verticalOffset: verticalOffset,
      verticalAxisDirection: verticalDetailsDirection,
      mainAxis: mainAxis,
      delegate: delegate as TwoDimensionalChildBuilderDelegate,
      childManager: context as TwoDimensionalChildManager,
      axis: axis,
      correctionsEnabled: correctionsEnabled,
    );
  }

  // The two `*AxisDirection` fields are named differently on the widget and
  // the render object; these keep createRenderObject readable.
  AxisDirection get verticalDetailsDirection {
    return verticalAxisDirection;
  }

  AxisDirection get horizontalDetailsDirection {
    return horizontalAxisDirection;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTrialViewport renderObject,
  ) {
    renderObject
      ..horizontalOffset = horizontalOffset
      ..horizontalAxisDirection = horizontalAxisDirection
      ..verticalOffset = verticalOffset
      ..verticalAxisDirection = verticalAxisDirection
      ..mainAxis = mainAxis
      ..delegate = delegate;
  }
}

class RenderTrialViewport extends RenderTwoDimensionalViewport {
  RenderTrialViewport({
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required TwoDimensionalChildBuilderDelegate delegate,
    required super.mainAxis,
    required super.childManager,
    required this.axis,
    required this.correctionsEnabled,
  }) : super(delegate: delegate);

  final LazyTrackAxis axis;

  /// When false the probe measures and places exactly as it otherwise
  /// would, but never calls `correctBy`. This is the control arm.
  final bool correctionsEnabled;

  /// Placement passes the last `layoutChildSequence` needed. 1 means no
  /// correction was required. Section 11 of the requirements asks for a
  /// fixed cap rather than a convergence loop, so this is also the number
  /// the cap has to bound.
  int debugLastPassCount = 0;

  /// Total corrections applied across the render object's life, so a test
  /// can assert the control arm really did skip them.
  int debugCorrectionCount = 0;

  /// Cap from section 11. Exceeding it is a defect, not a slow path.
  static const int kMaxPasses = 5;

  /// Vicinities already obtained during the CURRENT `layoutChildSequence`.
  ///
  /// This set is what makes a second placement pass legal.
  /// `buildOrObtainChildFor` is not idempotent within one pass: for an
  /// already-built vicinity it routes to `_reuseChild`, which does
  /// `_vicinityToChild.remove(vicinity)` and asserts the element was still
  /// present (`widgets/two_dimensional_viewport.dart:373-378`). It is a
  /// MOVE from the old child map to the new one, so calling it twice for
  /// one vicinity in one pass trips that assert. The first version of this
  /// trial did exactly that and failed; see the commit that precedes this
  /// one.
  final Set<ChildVicinity> _obtainedThisLayout = <ChildVicinity>{};

  /// Obtains a child at most once per `layoutChildSequence`, reading it
  /// back directly on any later request in the same call.
  RenderBox? _obtainOnce(ChildVicinity vicinity) {
    if (_obtainedThisLayout.add(vicinity)) {
      return buildOrObtainChildFor(vicinity);
    }
    return getChildFor(vicinity);
  }

  @override
  void layoutChildSequence() {
    _obtainedThisLayout.clear();
    var passes = 0;
    while (true) {
      passes++;
      final correction = _placeAndMeasure();
      final settled = correction.abs() < precisionErrorTolerance;
      if (settled || !correctionsEnabled || passes >= kMaxPasses) {
        break;
      }
      verticalOffset.correctBy(correction);
      debugCorrectionCount++;
    }
    debugLastPassCount = passes;
    assert(
      passes < kMaxPasses,
      "Correction loop hit its $kMaxPasses-pass cap without settling.",
    );

    // Final positioning sweep over EVERY vicinity obtained during this
    // call, not just the last pass's window. A correction moves the window,
    // so a child obtained by pass 1 can fall outside pass 2's range while
    // still being active for the frame; without this it would paint at an
    // offset computed against a superseded scroll position.
    _repositionAll();

    verticalOffset.applyContentDimensions(
      0.0,
      math.max(0.0, axis.totalExtent - viewportDimension.height),
    );
    horizontalOffset.applyContentDimensions(0.0, 0.0);
  }

  /// One placement pass. Builds and lays out the tracks intersecting the
  /// viewport, records any extent it discovers, and returns the scroll
  /// correction needed to hold the anchor still.
  ///
  /// THE ANCHOR IS THE FIRST ALREADY-MEASURED TRACK in the window, not the
  /// first visible one. That distinction is the whole correction. Scrolling
  /// up reveals tracks that have never been measured; measuring them is
  /// what shifts everything below. Anchoring on the first VISIBLE track
  /// would anchor on one of the newly revealed ones, whose own offset
  /// depends only on tracks before it that this pass never touched, so the
  /// computed correction would always be zero and the content already on
  /// screen would jump. Anchoring on the first track whose extent was
  /// already known measures exactly the displacement the user must not see.
  double _placeAndMeasure() {
    final scroll = verticalOffset.pixels;
    final firstTrack = axis.trackAt(scroll);
    final bottom = scroll + viewportDimension.height;

    var anchorTrack = -1;
    for (var track = firstTrack; track < kTrackCount; track++) {
      if (axis.offsetOf(track) >= bottom) {
        break;
      }
      if (axis.isMeasured(track)) {
        anchorTrack = track;
        break;
      }
    }
    final anchorOffsetBefore = anchorTrack < 0
        ? 0.0
        : axis.offsetOf(anchorTrack);

    for (var track = firstTrack; track < kTrackCount; track++) {
      if (axis.offsetOf(track) >= bottom) {
        break;
      }
      final child = _obtainOnce(ChildVicinity(xIndex: 0, yIndex: track));
      if (child == null) {
        continue;
      }
      child.layout(
        BoxConstraints.tightFor(
          width: viewportDimension.width,
          height: trueExtentOf(track),
        ),
        parentUsesSize: true,
      );
      // MEASUREMENT. The step that can invalidate offsets already used.
      if (!axis.isMeasured(track)) {
        axis.record(track, child.size.height);
      }
    }

    if (anchorTrack < 0) {
      return 0.0;
    }
    return axis.offsetOf(anchorTrack) - anchorOffsetBefore;
  }

  /// Writes every obtained child's `layoutOffset` from the settled axis
  /// state and the settled scroll position.
  void _repositionAll() {
    final scroll = verticalOffset.pixels;
    for (final vicinity in _obtainedThisLayout) {
      final child = getChildFor(vicinity);
      if (child == null) {
        continue;
      }
      parentDataOf(child).layoutOffset = Offset(
        0.0,
        axis.offsetOf(vicinity.yIndex) - scroll,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class TrialView extends TwoDimensionalScrollView {
  const TrialView({
    super.key,
    required super.verticalDetails,
    required TwoDimensionalChildBuilderDelegate delegate,
    required this.axis,
    required this.correctionsEnabled,
  }) : super(delegate: delegate, mainAxis: Axis.vertical);

  final LazyTrackAxis axis;
  final bool correctionsEnabled;

  @override
  Widget buildViewport(
    BuildContext context,
    ViewportOffset verticalOffset,
    ViewportOffset horizontalOffset,
  ) {
    return TrialViewport(
      horizontalOffset: horizontalOffset,
      horizontalAxisDirection: horizontalDetails.direction,
      verticalOffset: verticalOffset,
      verticalAxisDirection: verticalDetails.direction,
      mainAxis: mainAxis,
      delegate: delegate as TwoDimensionalChildBuilderDelegate,
      axis: axis,
      correctionsEnabled: correctionsEnabled,
    );
  }
}

Widget buildTrial({
  required ScrollController controller,
  required LazyTrackAxis axis,
  required bool correctionsEnabled,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: kViewportWidth,
        height: kViewportHeight,
        child: TrialView(
          verticalDetails: ScrollableDetails.vertical(controller: controller),
          axis: axis,
          correctionsEnabled: correctionsEnabled,
          delegate: TwoDimensionalChildBuilderDelegate(
            maxXIndex: 0,
            maxYIndex: kTrackCount - 1,
            builder: (context, vicinity) {
              return SizedBox(
                key: ValueKey<int>(vicinity.yIndex),
                width: kViewportWidth,
                height: trueExtentOf(vicinity.yIndex),
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// The track nearest the top of the viewport that is mounted both now and,
/// by construction, after a small upward scroll. Returns its key.
int topmostMountedTrack(WidgetTester tester) {
  var best = -1;
  var bestY = double.infinity;
  for (var track = 0; track < kTrackCount; track++) {
    final finder = find.byKey(ValueKey<int>(track));
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

void main() {
  const double scrollUpBy = 300.0;
  const double startOffset = 20000.0;

  testWidgets("SETUP SANITY: the scroll script measures tracks above the "
      "anchor, so a correction is genuinely required", (tester) async {
    final axis = LazyTrackAxis();
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildTrial(controller: controller, axis: axis, correctionsEnabled: true),
    );
    controller.jumpTo(startOffset);
    await tester.pumpAndSettle();

    final anchorAfterJump = axis.trackAt(controller.position.pixels);
    final offsetBefore = axis.offsetOf(anchorAfterJump);

    controller.jumpTo(controller.position.pixels - scrollUpBy);
    await tester.pumpAndSettle();

    // If this fails, the script never pulled an unmeasured track above the
    // anchor into a pass, and every other assertion here would pass
    // vacuously on a viewport that never corrects anything.
    expect(
      axis.offsetOf(anchorAfterJump),
      isNot(offsetBefore),
      reason: "Scrolling up must measure tracks before the anchor and move "
          "its structural offset; otherwise no correction is ever needed "
          "and this trial proves nothing.",
    );

    final render = tester.renderObject<RenderTrialViewport>(
      find.byType(TrialViewport),
    );
    expect(
      render.debugCorrectionCount,
      greaterThan(0),
      reason: "The corrected arm must actually have called correctBy.",
    );
  });

  testWidgets("CONTROL: without corrections the content moves by more than "
      "the user scrolled", (tester) async {
    final axis = LazyTrackAxis();
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildTrial(controller: controller, axis: axis, correctionsEnabled: false),
    );
    controller.jumpTo(startOffset);
    await tester.pumpAndSettle();

    final tracked = topmostMountedTrack(tester);
    expect(tracked, isNot(-1));
    final before = tester.getTopLeft(find.byKey(ValueKey<int>(tracked))).dy;

    controller.jumpTo(controller.position.pixels - scrollUpBy);
    await tester.pumpAndSettle();

    final after = tester.getTopLeft(find.byKey(ValueKey<int>(tracked))).dy;

    final render = tester.renderObject<RenderTrialViewport>(
      find.byType(TrialViewport),
    );
    expect(render.debugCorrectionCount, 0);
    expect(
      after - before,
      isNot(closeTo(scrollUpBy, 0.01)),
      reason: "This is the defect the correction exists to fix. If the "
          "uncorrected arm already holds the invariant, the corrected arm "
          "proves nothing.",
    );
  });

  testWidgets("TRIAL: with corrections the content moves by exactly what "
      "the user scrolled", (tester) async {
    final axis = LazyTrackAxis();
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildTrial(controller: controller, axis: axis, correctionsEnabled: true),
    );
    controller.jumpTo(startOffset);
    await tester.pumpAndSettle();

    final tracked = topmostMountedTrack(tester);
    expect(tracked, isNot(-1));
    final before = tester.getTopLeft(find.byKey(ValueKey<int>(tracked))).dy;

    controller.jumpTo(controller.position.pixels - scrollUpBy);
    await tester.pumpAndSettle();

    final after = tester.getTopLeft(find.byKey(ValueKey<int>(tracked))).dy;

    expect(
      after - before,
      closeTo(scrollUpBy, 0.01),
      reason: "The anchor must follow the finger and nothing else. A "
          "measurement of a track above it must not move it.",
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets("the correction loop settles well inside its cap", (
    tester,
  ) async {
    final axis = LazyTrackAxis();
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildTrial(controller: controller, axis: axis, correctionsEnabled: true),
    );

    var worst = 0;
    for (var offset = 20000.0; offset > 18000.0; offset -= 137.0) {
      controller.jumpTo(offset);
      await tester.pumpAndSettle();
      final render = tester.renderObject<RenderTrialViewport>(
        find.byType(TrialViewport),
      );
      worst = math.max(worst, render.debugLastPassCount);
    }

    expect(
      worst,
      greaterThanOrEqualTo(2),
      reason: "At least one jump in this script must actually need a "
          "correction. If every layout settled in one pass, the cap "
          "assertion below would hold vacuously on a viewport that never "
          "corrects anything.",
    );
    expect(
      worst,
      lessThan(RenderTrialViewport.kMaxPasses),
      reason: "A cap that is routinely hit is a convergence bug, not a "
          "slow path.",
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets("content dimensions and scroll position stay consistent after "
      "a correction", (tester) async {
    final axis = LazyTrackAxis();
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildTrial(controller: controller, axis: axis, correctionsEnabled: true),
    );
    controller.jumpTo(startOffset);
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.pixels - scrollUpBy);
    await tester.pumpAndSettle();

    final position = controller.position;
    expect(position.hasContentDimensions, isTrue);
    expect(position.pixels, greaterThanOrEqualTo(position.minScrollExtent));
    expect(position.pixels, lessThanOrEqualTo(position.maxScrollExtent));
    expect(
      position.maxScrollExtent,
      closeTo(
        math.max(0.0, axis.totalExtent - kViewportHeight),
        0.01,
      ),
      reason: "maxScrollExtent must reflect the extents measured so far, "
          "not the all-estimate total.",
    );
    expect(tester.takeException(), isNull);
  });
}
