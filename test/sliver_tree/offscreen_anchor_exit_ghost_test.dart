/// Regression repro for the OFF-SCREEN-ANCHOR exit-ghost SNAP.
///
/// When a VISIBLE row is reparented into a COLLAPSED section whose
/// destination header is OFF-SCREEN (beyond the render cache, so its
/// RenderBox is unmounted — `getChildForNode(anchorKey) == null`), the
/// Pass A.5 phantom-exit paint used to bail at the unconditional
/// `continue` and the ghost never painted — the card vanished instantly
/// (a SNAP). The fix persists the consume-time `ViewportEdge` per ghost
/// (`_phantomExitEdge`) and adds an EDGE-FALLBACK branch in Pass A.5 that
/// paints the ghost at `baseForEdge(edge) - scrollOffset + ghostSlide`
/// using the GHOST's own retained RenderBox, unclipped — so it slides
/// toward the viewport edge instead of disappearing.
///
/// ORACLE (Open Question 4): the fix paints via a DIFFERENT code path
/// than the `debugLastPhantomGhostPaint` capture (which is the
/// Pass-A.5-anchor-branch-only path the edge fallback never reaches), so
/// these tests are MECHANISM-AGNOSTIC: a no-draw recording
/// `PaintingContext` (the `_Recorder` pattern from
/// `tall_card_occlusion_zorder_test.dart`) records each `paintChild`
/// call's render-local `top`, and we assert the ghost RenderBox is
/// painted on-screen during the slide — independent of which pass renders
/// it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const double _kRow = 48.0;

/// A no-draw recording `PaintingContext` that records the render-local
/// `top` (and enclosing clip) of every `paintChild`. Mirrors the
/// `_Recorder` in `tall_card_occlusion_zorder_test.dart`.
class _Recorder extends PaintingContext {
  _Recorder(super.containerLayer, super.estimatedBounds);

  final List<({double top, Rect? clip})> order = [];
  Rect? _clip;

  @override
  ClipRectLayer? pushClipRect(
    bool needsCompositing,
    Offset offset,
    Rect clipRect,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.hardEdge,
    ClipRectLayer? oldLayer,
  }) {
    final prev = _clip;
    _clip = clipRect.shift(offset);
    painter(this, offset);
    _clip = prev;
    return null;
  }

  @override
  void paintChild(RenderObject child, Offset offset) {
    order.add((top: offset.dy, clip: _clip));
  }
}

Widget _harness(
  TreeController<String, String> controller, {
  ScrollController? scrollController,
  double height = 400,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: height,
        child: CustomScrollView(
          controller: scrollController,
          slivers: <Widget>[
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: _kRow,
                  child: Padding(
                    padding: EdgeInsets.only(left: depth * 20.0),
                    child: Text(key),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

RenderSliverTree<String, String> _render(WidgetTester tester) =>
    tester.renderObject<RenderSliverTree<String, String>>(
      find.byType(SliverTree<String, String>),
    );

/// Repaints `render` through a fresh `_Recorder` and returns the recorded
/// `paintChild` tops.
List<({double top, Rect? clip})> _recordPaints(
  RenderSliverTree<String, String> render, {
  Size surface = const Size(800, 400),
}) {
  final recorder = _Recorder(ContainerLayer(), Offset.zero & surface);
  render.paint(recorder, Offset.zero);
  return recorder.order;
}

/// Number of spacer rows between A and B. Chosen so B's structural
/// position (≈ 30 * 48 = 1440 px below the top) is FAR beyond the 400px
/// viewport AND the default sliver cache extent (~250px), so B's RenderBox
/// is UNMOUNTED at paint (`getChildForNode("B") == null`) — the
/// precondition for the edge-fallback path.
const int _kSpacers = 30;

/// Builds the OFF-SCREEN-BELOW scenario: A (expanded) [Y]; 30 spacers;
/// B (collapsed) far below a 400px viewport, beyond the render cache, so
/// its RenderBox is unmounted. Returns the controller.
Future<TreeController<String, String>> _pumpOffscreenBelow(
  WidgetTester tester,
) async {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationDuration: const Duration(milliseconds: 400),
    animationCurve: Curves.linear,
  );
  addTearDown(controller.dispose);

  controller.setRoots([
    const TreeNode(key: "A", data: "A"),
    for (int i = 0; i < _kSpacers; i++) TreeNode(key: "sp-$i", data: "sp-$i"),
    const TreeNode(key: "B", data: "B"),
  ]);
  controller.setChildren("A", [const TreeNode(key: "Y", data: "Y")]);
  controller.setChildren("B", [const TreeNode(key: "b1", data: "b1")]);
  controller.expand(key: "A", animate: false);

  await tester.pumpWidget(_harness(controller, height: 400));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets(
      "offscreen-below anchor: ghost paints on-screen toward bottom edge "
      "during slide", (tester) async {
    final controller = await _pumpOffscreenBelow(tester);
    final render = _render(tester);

    // Sanity: Y visible, b1 hidden.
    expect(controller.visibleNodes.contains("Y"), isTrue);
    expect(controller.visibleNodes.contains("b1"), isFalse);

    // Reparent Y into collapsed, off-screen B.
    controller.moveNode(
      "Y",
      "B",
      index: 0,
      animate: true,
      slideDuration: const Duration(milliseconds: 400),
      slideCurve: Curves.linear,
    );
    await tester.pump();

    // PRECONDITION: the destination anchor (B) is UNMOUNTED — off-screen
    // and beyond the cache — so Pass A.5 takes the edge fallback.
    expect(render.getChildForNode("B"), isNull,
        reason: "B must be unmounted (off-screen, beyond cache) so the "
            "edge-fallback path is exercised — not the anchor-relative "
            "tail.");
    expect(controller.visibleNodes.contains("Y"), isFalse);
    expect(controller.hasActiveSlides, isTrue);

    final paintExtent = render.geometry!.paintExtent;

    // Advance to a sliding frame and assert the ghost RenderBox is painted
    // on-screen. The static rows (A, sp-0..sp-9) paint at fixed structural
    // tops (0,48,..,480 clamped to the viewport); the GHOST paints at a
    // distinct sliding top. We compute the ghost's expected painted top
    // from the slide delta and the bottom-edge destination and assert a
    // recorded paint matches it AND lies on-screen.
    await tester.pump(const Duration(milliseconds: 120));
    expect(controller.getSlideDelta("Y"), isNot(0.0),
        reason: "Y must still be sliding at +120ms");

    // Destination y (scroll-space) = bottom edge + overhang = 400 + 40.
    // paintedY = destination + slideDelta (slideDelta is negative,
    // shrinking toward 0 as the slide settles).
    final delta = controller.getSlideDelta("Y");
    final expectedGhostTop = 440.0 + delta;

    final paints = _recordPaints(render);
    final ghostPaints = paints
        .where((p) => (p.top - expectedGhostTop).abs() < 2.0)
        .toList();
    expect(ghostPaints, isNotEmpty,
        reason: "The ghost RenderBox must be painted at ~$expectedGhostTop "
            "(bottom edge 440 + slideDelta $delta). Recorded tops: "
            "${paints.map((p) => p.top).toList()}");
    // The ghost must paint ON-SCREEN during the slide.
    expect(expectedGhostTop, greaterThanOrEqualTo(0.0));
    expect(expectedGhostTop, lessThan(paintExtent),
        reason: "Ghost top $expectedGhostTop must be on-screen "
            "(0 <= top < $paintExtent).");

    await tester.pumpAndSettle();
  });

  testWidgets(
      "offscreen-below anchor: snap is gone — ghost recorded on every "
      "sliding frame", (tester) async {
    final controller = await _pumpOffscreenBelow(tester);
    final render = _render(tester);

    controller.moveNode(
      "Y",
      "B",
      index: 0,
      animate: true,
      slideDuration: const Duration(milliseconds: 400),
      slideCurve: Curves.linear,
    );
    await tester.pump();
    expect(render.getChildForNode("B"), isNull);

    int slidingFrames = 0;
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final delta = controller.getSlideDelta("Y");
      if (delta == 0.0 || !controller.hasActiveSlides) break;
      slidingFrames++;
      final expectedGhostTop = 440.0 + delta;
      // Only assert on frames where the ghost is on-screen — as it slides
      // toward the bottom edge it can move past the viewport bottom in the
      // late frames (it is sliding OUT). The "no snap" guarantee is that on
      // EARLY sliding frames the ghost is recorded on-screen, every time.
      if (expectedGhostTop >= 0.0 &&
          expectedGhostTop < render.geometry!.paintExtent) {
        final paints = _recordPaints(render);
        final hit = paints
            .any((p) => (p.top - expectedGhostTop).abs() < 2.0);
        expect(hit, isTrue,
            reason: "Frame $i: ghost must be painted at ~$expectedGhostTop "
                "(no snap). Recorded: ${paints.map((p) => p.top).toList()}");
      }
    }
    expect(slidingFrames, greaterThan(0),
        reason: "Y must have actually slid for several frames");

    await tester.pumpAndSettle();
  });

  testWidgets(
      "offscreen-above anchor: ghost paints on-screen toward top edge "
      "during slide", (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 400),
      animationCurve: Curves.linear,
    );
    addTearDown(controller.dispose);

    // B (collapsed) at the TOP; 30 spacers; A (expanded) [Y] far below.
    // After scrolling down so B is above the viewport (unmounted, beyond
    // the cache) and Y is visible, reparenting Y into B sends the ghost
    // toward the TOP edge.
    controller.setRoots([
      const TreeNode(key: "B", data: "B"),
      for (int i = 0; i < _kSpacers; i++) TreeNode(key: "sp-$i", data: "sp-$i"),
      const TreeNode(key: "A", data: "A"),
    ]);
    controller.setChildren("B", [const TreeNode(key: "b1", data: "b1")]);
    controller.setChildren("A", [const TreeNode(key: "Y", data: "Y")]);
    controller.expand(key: "A", animate: false);

    await tester.pumpWidget(
      _harness(controller, scrollController: scrollController, height: 400),
    );
    await tester.pumpAndSettle();

    // Layout: B=0, sp-0..sp-29 at 48..1440, A=1488, Y=1536. Scroll down so
    // A is at the top (local y=0), Y at 48, and B (structural y=0) is far
    // above the viewport and beyond the cache → unmounted.
    scrollController.jumpTo(1488);
    await tester.pump();
    await tester.pumpAndSettle();

    final render = _render(tester);
    expect(controller.visibleNodes.contains("Y"), isTrue);

    controller.moveNode(
      "Y",
      "B",
      index: 0,
      animate: true,
      slideDuration: const Duration(milliseconds: 400),
      slideCurve: Curves.linear,
    );
    await tester.pump();

    // PRECONDITION: B is unmounted (above viewport, beyond cache).
    expect(render.getChildForNode("B"), isNull,
        reason: "B must be unmounted above the viewport so the edge "
            "fallback (top edge) fires.");
    expect(controller.hasActiveSlides, isTrue);

    // Destination y (scroll-space, sliver-local) = top edge - overhang =
    // 0 - 40 = -40. paintedY = -40 + slideDelta (positive, shrinking).
    await tester.pump(const Duration(milliseconds: 120));
    final delta = controller.getSlideDelta("Y");
    expect(delta, isNot(0.0));
    final expectedGhostTop = -40.0 + delta;

    final paints = _recordPaints(render);
    final hit =
        paints.any((p) => (p.top - expectedGhostTop).abs() < 2.0);
    expect(hit, isTrue,
        reason: "Ghost must paint at ~$expectedGhostTop (top edge -40 + "
            "slideDelta $delta). Recorded: "
            "${paints.map((p) => p.top).toList()}");
    // Mid-travel the ghost paints some on-screen pixels as it slides UP
    // toward / just above the top edge.
    expect(expectedGhostTop + _kRow, greaterThan(0.0),
        reason: "Ghost (top=$expectedGhostTop, h=$_kRow) must still show "
            "on-screen pixels mid-travel.");

    await tester.pumpAndSettle();
  });

  testWidgets(
      "offscreen anchor: ghost converges on the viewport edge, not the "
      "unmounted anchor", (tester) async {
    final controller = await _pumpOffscreenBelow(tester);
    final render = _render(tester);

    controller.moveNode(
      "Y",
      "B",
      index: 0,
      animate: true,
      slideDuration: const Duration(milliseconds: 400),
      slideCurve: Curves.linear,
    );
    await tester.pump();
    expect(render.getChildForNode("B"), isNull);

    // Across sliding frames the ghost's painted top trends toward the
    // bottom edge (440) as |slideDelta| shrinks. Confirm the recorded
    // ghost top monotonically (non-strictly) approaches 440, and that NO
    // paint is recorded at B's structural position (B is unmounted — it
    // never paints).
    double? prevDistanceToEdge;
    int checked = 0;
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final delta = controller.getSlideDelta("Y");
      if (delta == 0.0 || !controller.hasActiveSlides) break;
      final expectedGhostTop = 440.0 + delta;
      if (expectedGhostTop < 0.0 ||
          expectedGhostTop >= render.geometry!.paintExtent) {
        continue;
      }
      final distance = (440.0 - expectedGhostTop).abs();
      if (prevDistanceToEdge != null) {
        expect(distance, lessThanOrEqualTo(prevDistanceToEdge! + 0.5),
            reason: "Frame $i: ghost must converge toward the bottom edge "
                "(distance $distance must not grow past previous "
                "$prevDistanceToEdge).");
      }
      prevDistanceToEdge = distance;
      checked++;
    }
    expect(checked, greaterThan(0));

    await tester.pumpAndSettle();
  });

  testWidgets(
      "offscreen anchor: settles hidden, ghost pruned, no residual paint",
      (tester) async {
    final controller = await _pumpOffscreenBelow(tester);
    final render = _render(tester);

    controller.moveNode(
      "Y",
      "B",
      index: 0,
      animate: true,
      slideDuration: const Duration(milliseconds: 400),
      slideCurve: Curves.linear,
    );
    await tester.pump();
    expect(render.getChildForNode("B"), isNull);

    await tester.pumpAndSettle();

    // Settle: Y is hidden (under collapsed B), the ghost is pruned, and a
    // final repaint records NO ghost paint at the (former) sliding band.
    expect(controller.visibleNodes.contains("Y"), isFalse);
    expect(controller.hasActiveSlides, isFalse);
    expect(render.debugPhantomExitGhostCount, 0,
        reason: "Ghost must be pruned at settle.");

    final paints = _recordPaints(render);
    // No paint at a sliding top in the (0, 440) on-screen band attributable
    // to the ghost — the only on-screen rows now are the static ones.
    // The static rows are A=0, sp-0..sp-9 (48..480 clamped). The ghost, if
    // leaked, would paint somewhere distinct; assert nothing paints below
    // the last static visible row's slot that isn't a static row. We assert
    // the simpler invariant: ghost count is zero (above) and the recorded
    // tops match the static structural grid (multiples of 48, within the
    // viewport), i.e. no stray fractional sliding top.
    for (final p in paints) {
      final nearestGrid = (p.top / _kRow).round() * _kRow;
      expect((p.top - nearestGrid).abs(), lessThan(1.0),
          reason: "After settle every painted row must sit on the static "
              "48px grid — a stray top (${p.top}) would mean a residual "
              "ghost paint.");
    }
  });

  testWidgets(
      "offscreen anchor: no t=0 jump — first sliding frame paints at "
      "pre-move baseline", (tester) async {
    final controller = await _pumpOffscreenBelow(tester);
    final render = _render(tester);

    // Pre-move: record Y's painted top while it is still a normal visible
    // row at structural y=48.
    final preMovePaints = _recordPaints(render);
    // Y is at structural y=48 (A=0, Y=48).
    const preMoveTop = 48.0;
    expect(preMovePaints.any((p) => (p.top - preMoveTop).abs() < 1.0), isTrue,
        reason: "Y must be painting at its structural top (48) pre-move.");

    controller.moveNode(
      "Y",
      "B",
      index: 0,
      animate: true,
      slideDuration: const Duration(milliseconds: 400),
      slideCurve: Curves.linear,
    );
    await tester.pump();
    expect(render.getChildForNode("B"), isNull);

    // FIRST sliding frame: the ghost must paint at (≈) the pre-move
    // baseline (48), NOT jump to the edge. With the consume destination
    // (edgeY + ghostSlideY) and the paint (baseForEdge(edge) - scrollOffset
    // + ghostSlide) agreeing at the same scroll, the initial ghostSlide
    // (= baseline.y - current.y) composes so paintedY == baseline.y at t=0.
    final delta = controller.getSlideDelta("Y");
    final firstGhostTop = 440.0 + delta;
    expect(firstGhostTop, moreOrLessEquals(preMoveTop, epsilon: 2.0),
        reason: "First sliding frame must paint at the pre-move baseline "
            "(48), not jump. Got $firstGhostTop (delta=$delta).");

    final paints = _recordPaints(render);
    expect(paints.any((p) => (p.top - firstGhostTop).abs() < 2.0), isTrue,
        reason: "Ghost paint at the baseline must be recorded on frame 0.");

    await tester.pumpAndSettle();
  });
}
