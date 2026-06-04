/// Regression repro for the ADJACENT-ROW exit-ghost VANISH.
///
/// When a VISIBLE row is reparented into a COLLAPSED parent whose
/// destination header sits DIRECTLY BELOW the moved row, the row's pre-move
/// baseline equals the header's SETTLED position — the header slides up
/// exactly one row into the vacated slot, so the exit ghost's own FLIP
/// delta is ZERO.
///
/// THE BUG: Pass A.5 converged the ghost on the header's LIVE (sliding) band
/// top (`_anchorPaintedBounds`, which adds the anchor's own slide). A
/// zero-delta ghost therefore pinned to the live band top, and the EXIT
/// down-clip (`visible = [0, bandTop]`) clipped it to NOTHING every frame —
/// the card vanished in place while the section size-animated. Pass A.5's
/// guard and Step-0a's prune also reaped it as "settled" (own delta 0).
///
/// THE FIX (this test guards it):
///   1. converge the ghost on the anchor's SETTLED top (no anchor-slide term),
///   2. keep the EXIT clip on the LIVE band (so the rising header occludes it),
///   3. keep a zero-own-slide ghost alive/painted while its anchor still slides.
/// Result: the stationary ghost is VISIBLY ABSORBED by the rising header
/// instead of vanishing.
///
/// ORACLE: a clip-stack-INTERSECTING recording `PaintingContext` measures the
/// ghost RenderBox's true on-screen height each frame = `rect ∩ clipStack ∩
/// viewport`. This is mechanism-agnostic and, unlike `debugLastPhantomGhostPaint`,
/// accounts for the EXIT clip (the exact thing that produced the vanish).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const double _kRow = 48.0;
const Size _kSurface = Size(800, 400);

/// A no-draw recording `PaintingContext` that INTERSECTS the full clip stack
/// (not just the innermost clip) and records each `paintChild`'s render-local
/// rect together with the intersected clip — so we can compute the true
/// on-screen (clipped) area of a specific child.
class _Recorder extends PaintingContext {
  _Recorder(super.containerLayer, super.estimatedBounds);

  final List<({RenderObject child, Rect rect, Rect clip})> painted = [];
  Rect _clip = const Rect.fromLTWH(-100000, -100000, 200000, 200000);

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
    _clip = prev.intersect(clipRect.shift(offset));
    painter(this, offset);
    _clip = prev;
    return null;
  }

  @override
  void paintChild(RenderObject child, Offset offset) {
    final size = child is RenderBox ? child.size : Size.zero;
    painted.add((child: child, rect: offset & size, clip: _clip));
  }
}

Widget _harness(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: _kSurface.height,
        width: _kSurface.width,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) => SizedBox(
                key: ValueKey("row-$key"),
                height: _kRow,
                child: Text(key),
              ),
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

/// Builds: A (expanded) [a0,a1,a2]; B (collapsed) [b0]. Visible order with B
/// collapsed: A(0), a0(48), a1(96), a2(144), B(192). So a2 is the LAST row of
/// A, sitting DIRECTLY above the collapsed B header — the adjacency that makes
/// the exit-ghost FLIP delta zero when a2 reparents into B.
Future<TreeController<String, String>> _pumpTree(WidgetTester tester) async {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationDuration: const Duration(milliseconds: 400),
    animationCurve: Curves.linear,
  );
  addTearDown(controller.dispose);

  controller.setRoots([
    const TreeNode(key: "A", data: "A"),
    const TreeNode(key: "B", data: "B"),
  ]);
  controller.setChildren("A", [
    const TreeNode(key: "a0", data: "a0"),
    const TreeNode(key: "a1", data: "a1"),
    const TreeNode(key: "a2", data: "a2"),
  ]);
  controller.setChildren("B", [const TreeNode(key: "b0", data: "b0")]);
  controller.expand(key: "A", animate: false);
  // B stays collapsed.

  await tester.pumpWidget(_harness(controller));
  await tester.pumpAndSettle();
  return controller;
}

/// One frame sample of the moved ghost: its painted rect top, its true
/// on-screen (clipped ∩ viewport) visible height, and its live slide delta.
typedef _Sample = ({double top, double visible, double delta});

/// Reparents [moveKey] into collapsed [dest] and samples the ghost every
/// 16ms for the duration of the slide.
Future<List<_Sample>> _sampleExit(
  WidgetTester tester,
  TreeController<String, String> controller,
  RenderSliverTree<String, String> render, {
  required String moveKey,
  required String dest,
}) async {
  controller.moveNode(
    moveKey,
    dest,
    index: 0,
    animate: true,
    slideDuration: const Duration(milliseconds: 400),
    slideCurve: Curves.linear,
  );
  await tester.pump();

  final paintExtent = render.geometry!.paintExtent;
  final viewport = Rect.fromLTWH(0, 0, _kSurface.width, paintExtent);

  final samples = <_Sample>[];
  for (int i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (!controller.hasActiveSlides) break;
    final delta = controller.getSlideDelta(moveKey);
    final ghostBox = render.getChildForNode(moveKey);
    if (ghostBox == null) {
      samples.add((top: double.nan, visible: 0.0, delta: delta));
      continue;
    }
    final recorder = _Recorder(ContainerLayer(), Offset.zero & _kSurface);
    render.paint(recorder, Offset.zero);
    double vis = 0.0;
    double top = double.nan;
    for (final p in recorder.painted) {
      if (!identical(p.child, ghostBox)) continue;
      final v = p.rect.intersect(p.clip).intersect(viewport);
      final h = (v.width > 0 && v.height > 0) ? v.height : 0.0;
      if (h > vis) {
        vis = h;
        top = p.rect.top;
      }
    }
    samples.add((top: top, visible: vis, delta: delta));
  }
  return samples;
}

double _maxVisible(List<_Sample> s) =>
    s.fold(0.0, (a, b) => math.max(a, b.visible));

/// Longest run of consecutive frames whose visible height exceeds [floor].
int _longestVisibleRun(List<_Sample> s, {double floor = 2.0}) {
  int best = 0, run = 0;
  for (final sample in s) {
    if (sample.visible > floor) {
      run++;
      best = math.max(best, run);
    } else {
      run = 0;
    }
  }
  return best;
}

void main() {
  testWidgets(
      "adjacent exit ghost is VISIBLY absorbed, not vanished in place",
      (tester) async {
    final controller = await _pumpTree(tester);
    final render = _render(tester);

    // Preconditions: a2 visible & directly above the MOUNTED collapsed B.
    expect(controller.visibleNodes.contains("a2"), isTrue);
    expect(controller.visibleNodes.contains("b0"), isFalse);
    expect(render.getChildForNode("B"), isNotNull,
        reason: "destination header B must be on-screen & mounted "
            "(adjacent, anchor-relative path — NOT the off-screen edge path)");

    final samples = await _sampleExit(tester, controller, render,
        moveKey: "a2", dest: "B");

    // The defining symptom of THIS bug is a ZERO own-slide ghost (its baseline
    // already equals the settled header position) — confirm we exercised it.
    expect(samples.every((s) => s.delta.abs() < 0.5), isTrue,
        reason: "adjacent ghost must have ~zero own FLIP delta "
            "(this is the degenerate case the bug mishandled)");

    expect(_maxVisible(samples), greaterThan(10.0),
        reason: "the stationary ghost must be VISIBLY on screen (absorbed by "
            "the rising header) at some frame — the bug clips it to 0 every "
            "frame. Visible heights: ${samples.map((s) => s.visible).toList()}");

    await tester.pumpAndSettle();
  });

  testWidgets(
      "adjacent exit ghost is SUSTAINED >= 5 consecutive frames (no 1-frame blip)",
      (tester) async {
    final controller = await _pumpTree(tester);
    final render = _render(tester);

    final samples = await _sampleExit(tester, controller, render,
        moveKey: "a2", dest: "B");

    expect(_longestVisibleRun(samples), greaterThanOrEqualTo(5),
        reason: "absorption must be a SUSTAINED slide, not a single-frame "
            "flash. Visible heights: ${samples.map((s) => s.visible).toList()}");

    await tester.pumpAndSettle();
  });

  testWidgets(
      "adjacent exit ghost stays at its baseline — does NOT chase the live header",
      (tester) async {
    final controller = await _pumpTree(tester);
    final render = _render(tester);

    final samples = await _sampleExit(tester, controller, render,
        moveKey: "a2", dest: "B");

    // Only frames where the ghost is actually on screen (the bug yields none,
    // so this also fails-red under the regression).
    final tops = samples
        .where((s) => s.visible > 2.0 && !s.top.isNaN)
        .map((s) => s.top)
        .toList();
    expect(tops, isNotEmpty,
        reason: "ghost must be visible on some frame (else it vanished)");

    // a2's pre-move structural top is 144 (A=0,a0=48,a1=96,a2=144). The fix
    // paints the ghost STATIONARY there while the header rises to absorb it.
    // The bug would paint it chasing the live band top (192 -> 144), a moving
    // top with a large spread (and clipped to nothing anyway).
    final spread = tops.reduce(math.max) - tops.reduce(math.min);
    expect(spread, lessThan(8.0),
        reason: "stationary ghost (header rises onto it), not chasing it. "
            "Tops: $tops");
    expect(tops.first, moreOrLessEquals(144.0, epsilon: 4.0),
        reason: "ghost sits at a2's pre-move baseline (144), no t=0 jump");

    await tester.pumpAndSettle();
  });

  testWidgets(
      "FAR row still slides visibly into the collapsed header (discrimination)",
      (tester) async {
    final controller = await _pumpTree(tester);
    final render = _render(tester);

    // a0 is the FIRST child (far from B): it has a real, large FLIP delta and
    // must slide DOWN into the header. This proves the oracle distinguishes a
    // genuine slide from a vanish — the adjacent assertions are not trivially
    // green.
    final samples = await _sampleExit(tester, controller, render,
        moveKey: "a0", dest: "B");

    expect(samples.any((s) => s.delta.abs() > 1.0), isTrue,
        reason: "far row must have a real (non-zero) exit slide");
    expect(_maxVisible(samples), greaterThan(10.0),
        reason: "far row's ghost must be visibly on screen during its slide");

    await tester.pumpAndSettle();
  });

  testWidgets(
      "adjacent exit ghost settles hidden, ghost pruned, no residual paint",
      (tester) async {
    final controller = await _pumpTree(tester);
    final render = _render(tester);

    await _sampleExit(tester, controller, render, moveKey: "a2", dest: "B");
    await tester.pumpAndSettle();

    expect(controller.visibleNodes.contains("a2"), isFalse,
        reason: "a2 ends hidden under collapsed B");
    expect(controller.hasActiveSlides, isFalse);
    expect(render.debugPhantomExitGhostCount, 0,
        reason: "ghost must be pruned once BOTH it and its anchor settle "
            "(the relaxed prune must not leak it)");

    // Final repaint: every painted row sits on the static 48px grid — no stray
    // residual ghost paint.
    final recorder = _Recorder(ContainerLayer(), Offset.zero & _kSurface);
    render.paint(recorder, Offset.zero);
    for (final p in recorder.painted) {
      final nearestGrid = (p.rect.top / _kRow).round() * _kRow;
      expect((p.rect.top - nearestGrid).abs(), lessThan(1.0),
          reason: "stray top ${p.rect.top} after settle ⇒ residual ghost");
    }
  });
}
