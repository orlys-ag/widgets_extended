/// Audit repro for finding f13: the consume-time `_phantomClipAnchors` prune
/// (render_sliver_tree.dart Step inside `_consumeSlideBaselineIfAny`) strips
/// the EXIT clip of a still-absorbing ADJACENT exit ghost.
///
/// Scenario: a2 sits DIRECTLY above collapsed B. `moveNode("a2","B")` makes
/// a2 an exit ghost with ZERO own FLIP delta (its baseline already equals the
/// header's settled position) while B slides up to absorb it. Mid-absorption,
/// an UNRELATED animated move ("c0" -> "D") stages+consumes a second slide
/// baseline. The consume-time lazy-prune removes `_phantomClipAnchors["a2"]`
/// because a2's own slide delta is 0 — but Step 0a's lockstep prune
/// deliberately KEEPS a2 in `_phantomExitGhosts` while its anchor (B) is
/// still sliding. Result: Pass A.5 keeps painting the ghost but
/// `_resolvePhantomAnchorBounds` now returns null, so the ghost paints
/// UNCLIPPED (re-exposed far overhang for a card taller than the header).
///
/// EXPECTED (correct) behavior asserted here: a still-absorbing adjacent
/// exit ghost keeps its EXIT clip across an unrelated consume — i.e. the
/// consume-time prune must use the same "ghost AND anchor both settled"
/// criterion as `_pruneSettledPhantomExitGhosts`.
///
/// Oracles:
///  1. `debugLastPhantomGhostPaint["a2"].clipRect` must stay non-null while
///     the ghost is still absorbing (mechanism-level; matches the finding).
///  2. A clip-stack-intersecting recording `PaintingContext` (same oracle as
///     adjacent_collapsed_exit_ghost_test.dart) proves a TALL card's visible
///     paint stays bounded to `[0, bandTop]` (downward EXIT clip) — the
///     stripped clip re-exposes paint past the live band (visual artifact).
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const double _kRow = 48.0;
const double _kTallRow = 160.0;
const Size _kSurface = Size(800, 400);
const Duration _kSlide = Duration(milliseconds: 1000);

/// A no-draw recording `PaintingContext` that INTERSECTS the full clip stack
/// and records each `paintChild`'s render-local rect together with the
/// intersected clip — so the true on-screen (clipped) region of a specific
/// child can be computed. Copied from adjacent_collapsed_exit_ghost_test.dart.
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

Widget _harness(
  TreeController<String, String> controller, {
  double Function(String key)? heightFor,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: _kSurface.height,
        width: _kSurface.width,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                final double height =
                    heightFor != null ? heightFor(key) : _kRow;
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: height,
                  child: Text(key),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

RenderSliverTree<String, String> _render(WidgetTester tester) {
  return tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
}

/// Builds: A (expanded) [a0,a1,a2]; B (collapsed) [b0]; C (expanded) [c0,c1];
/// D (expanded) [d0]. a2 is the LAST row of A, sitting DIRECTLY above the
/// collapsed B header — the adjacency that makes the exit-ghost FLIP delta
/// zero when a2 reparents into B. C/D provide the UNRELATED rows for the
/// overlapping second mutation.
Future<TreeController<String, String>> _pumpTree(
  WidgetTester tester, {
  double Function(String key)? heightFor,
}) async {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationDuration: const Duration(milliseconds: 400),
    animationCurve: Curves.linear,
  );
  addTearDown(controller.dispose);

  controller.setRoots([
    const TreeNode(key: "A", data: "A"),
    const TreeNode(key: "B", data: "B"),
    const TreeNode(key: "C", data: "C"),
    const TreeNode(key: "D", data: "D"),
  ]);
  controller.setChildren("A", [
    const TreeNode(key: "a0", data: "a0"),
    const TreeNode(key: "a1", data: "a1"),
    const TreeNode(key: "a2", data: "a2"),
  ]);
  controller.setChildren("B", [const TreeNode(key: "b0", data: "b0")]);
  controller.setChildren("C", [
    const TreeNode(key: "c0", data: "c0"),
    const TreeNode(key: "c1", data: "c1"),
  ]);
  controller.setChildren("D", [const TreeNode(key: "d0", data: "d0")]);
  controller.expand(key: "A", animate: false);
  controller.expand(key: "C", animate: false);
  controller.expand(key: "D", animate: false);
  // B stays collapsed.

  await tester.pumpWidget(_harness(controller, heightFor: heightFor));
  await tester.pumpAndSettle();
  return controller;
}

/// Starts the adjacent absorption (a2 -> collapsed B) and pumps to
/// mid-absorption, verifying the zero-own-delta ghost + live clip
/// preconditions that define this finding's window.
Future<void> _startAdjacentAbsorption(
  WidgetTester tester,
  TreeController<String, String> controller,
  RenderSliverTree<String, String> render,
) async {
  controller.moveNode(
    "a2",
    "B",
    index: 0,
    animate: true,
    slideDuration: _kSlide,
    slideCurve: Curves.linear,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));

  expect(controller.getSlideDelta("a2").abs(), lessThan(0.5),
      reason: "setup: adjacent ghost must have ~zero own FLIP delta "
          "(the degenerate case this finding targets)");
  expect(controller.getSlideDelta("B").abs(), greaterThan(1.0),
      reason: "setup: destination header B must still be sliding up "
          "(absorption in flight)");
  expect(render.debugPhantomExitGhostCount, 1,
      reason: "setup: a2 must be a live exit ghost");
  expect(render.debugLastPhantomGhostPaint.containsKey("a2"), isTrue,
      reason: "setup: the absorbing ghost must be painted this frame");
  expect(render.debugLastPhantomGhostPaint["a2"]!.clipRect, isNotNull,
      reason: "setup: a healthy mid-absorption frame clips the ghost to "
          "the destination header's band");
}

/// Bounded drain — never an unbounded pumpAndSettle on a scene that might
/// not settle.
Future<void> _drain(
  WidgetTester tester,
  TreeController<String, String> controller,
) async {
  for (int i = 0; i < 150; i++) {
    if (!controller.hasActiveSlides) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  for (int i = 0; i < 100; i++) {
    if (!tester.binding.hasScheduledFrame) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets(
    "f13: unrelated overlapping move must NOT strip the EXIT clip of a "
    "still-absorbing adjacent exit ghost",
    (tester) async {
      final controller = await _pumpTree(tester);
      final render = _render(tester);

      await _startAdjacentAbsorption(tester, controller, render);

      // Overlapping, UNRELATED animated mutation while B is mid-absorption:
      // c0 (under C, below B) reparents into expanded D. This stages and
      // consumes a SECOND slide baseline — the consume-time prune window.
      controller.moveNode(
        "c0",
        "D",
        index: 0,
        animate: true,
        slideDuration: _kSlide,
        slideCurve: Curves.linear,
      );
      await tester.pump(const Duration(milliseconds: 16));

      // Post-mutation sanity: the ghost is still absorbing and still painted
      // (Step 0a's lockstep prune keeps it while the anchor slides).
      expect(controller.getSlideDelta("B").abs(), greaterThan(1.0),
          reason: "setup: B must still be absorbing after the unrelated move");
      expect(render.debugPhantomExitGhostCount, greaterThanOrEqualTo(1),
          reason: "setup: a2's exit ghost must survive the unrelated consume");
      expect(render.debugLastPhantomGhostPaint.containsKey("a2"), isTrue,
          reason: "setup: the still-absorbing ghost must be painted this "
              "frame");

      // EXPECTED behavior: the EXIT clip is retained for the whole time the
      // ghost keeps painting. A null clip here means the consume-time
      // _phantomClipAnchors prune (ghost-delta-only criterion) stripped the
      // entry while _phantomExitGhosts (ghost+anchor criterion) kept the
      // ghost alive — the f13 map desync.
      expect(render.debugLastPhantomGhostPaint["a2"]!.clipRect, isNotNull,
          reason: "a still-absorbing adjacent exit ghost must keep its EXIT "
              "clip across an unrelated consume (f13: consume-time prune "
              "must match _pruneSettledPhantomExitGhosts' ghost+anchor "
              "settled criterion)");

      await _drain(tester, controller);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    "f13: TALL adjacent exit ghost stays band-clipped after an unrelated "
    "overlapping move (no re-exposed overhang past the live band top)",
    (tester) async {
      final controller = await _pumpTree(tester, heightFor: (key) {
        return key == "a2" ? _kTallRow : _kRow;
      });
      final render = _render(tester);

      await _startAdjacentAbsorption(tester, controller, render);

      // Overlapping, unrelated animated mutation (same as test 1).
      controller.moveNode(
        "c0",
        "D",
        index: 0,
        animate: true,
        slideDuration: _kSlide,
        slideCurve: Curves.linear,
      );
      await tester.pump(const Duration(milliseconds: 16));
      // Let absorption progress until the tall card's bottom pokes past the
      // live band's BOTTOM — the window where the stripped clip re-exposes
      // the true far overhang (not even the header repaint covers it).
      await tester.pump(const Duration(milliseconds: 200));

      expect(controller.getSlideDelta("B").abs(), greaterThan(1.0),
          reason: "setup: B must still be absorbing at the sample frame");

      final recorder = _Recorder(ContainerLayer(), Offset.zero & _kSurface);
      render.paint(recorder, Offset.zero);

      final capture = render.debugLastPhantomGhostPaint["a2"];
      expect(capture, isNotNull,
          reason: "setup: ghost must be painted at the sample frame");
      final double bandTop = capture!.anchorBand.top;
      final double bandBottom = capture.anchorBand.bottom;

      // Discrimination sanity: unclipped, the tall card's raw painted rect
      // overhangs past the band BOTTOM this frame, so the EXIT clip is
      // load-bearing (a pass could not be trivial).
      expect(capture.ghostRect.bottom, greaterThan(bandBottom + 5.0),
          reason: "setup: sample frame must be one where the raw ghost rect "
              "overhangs the live band (clip is load-bearing)");

      final ghostBox = render.getChildForNode("a2");
      expect(ghostBox, isNotNull,
          reason: "setup: ghost RenderBox must still be retained");

      double visibleBottom = double.negativeInfinity;
      bool painted = false;
      for (final p in recorder.painted) {
        if (!identical(p.child, ghostBox)) {
          continue;
        }
        painted = true;
        final visible = p.rect.intersect(p.clip);
        if (visible.width > 0 &&
            visible.height > 0 &&
            visible.bottom > visibleBottom) {
          visibleBottom = visible.bottom;
        }
      }
      expect(painted, isTrue,
          reason: "setup: ghost RenderBox must be painted this frame");

      // EXPECTED behavior: the downward EXIT clip bounds the ghost's visible
      // paint to [0, bandTop]. Visible paint below the live band top (and in
      // this frame even below bandBottom — the re-exposed far overhang)
      // means the clip was stripped by the consume-time prune (f13).
      expect(visibleBottom, lessThanOrEqualTo(bandTop + 0.5),
          reason: "the EXIT clip must bound the absorbed tall card to "
              "[0, bandTop=$bandTop] (bandBottom=$bandBottom); visible paint "
              "reaching $visibleBottom means the clip was stripped while the "
              "ghost was still absorbing (f13)");

      await _drain(tester, controller);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
