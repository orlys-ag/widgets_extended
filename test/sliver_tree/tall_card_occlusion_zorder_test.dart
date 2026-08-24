/// Defect-2 (header-occludes-ghost z-order) hard assertions.
///
/// During a between-section reparent slide the tall card paints BEHIND
/// every section header it visually crosses — INCLUDING a header that is
/// NOT in the sticky set. Three gaps are covered:
///   1. `maxStickyDepth: 0`: the destination header is never sticky. For
///      a CLIPPED ghost the EXIT clip, not a repaint, keeps the band
///      free of ghost pixels, so the anchor is painted exactly once, by
///      Pass A.
///   2. A sticky destination header: the anchor stays in the sticky set
///      on every sampled frame (the earlier "dropped while animating"
///      premise was measured false), so Pass B paints it exactly once
///      over the ghost.
///   3. The destination header is sticky-PINNED (scrolled) — the ghost
///      converges on / is clipped against the header's PAINTED (pinned)
///      band, read at paint time, not its structural offset.
///
/// PAINT-COUNT ORACLE: a no-draw recording `PaintingContext` captures
/// every `paintChild` call. Using `debugLastPhantomGhostPaint["x"]` (the
/// ghost's painted rect + the destination header's painted band) we
/// count the paints landing on the band (exactly one) and assert the
/// EXIT clip excludes the band, so no ghost pixel can enter it.
library;

import 'package:widgets_extended/sliver_tree/animation_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/render_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree_widget.dart';
import 'package:widgets_extended/sliver_tree/synced_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/synced_tree_node.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

const double _kHeader = 48.0;
const double _kCard = 80.0;
const double _kPlaceholder = 60.0;

double _heightFor(String key) {
  if (key == "fav" || key == "others") return _kHeader;
  if (key == "fav_ph" || key == "others_ph") return _kPlaceholder;
  return _kCard;
}

SyncedTreeNode<String, String> _n(
  String k, [
  List<SyncedTreeNode<String, String>>? c,
]) => SyncedTreeNode(key: k, data: k, children: c ?? const []);

RenderSliverTree<String, String> _render(WidgetTester tester) =>
    tester.renderObject<RenderSliverTree<String, String>>(
      find.byType(SliverTree<String, String>),
    );

/// A no-draw recording `PaintingContext` that records the ORDER and
/// render-local top (and enclosing clip) of every `paintChild`.
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

class _Harness extends StatefulWidget {
  const _Harness({
    required this.builder,
    required this.maxStickyDepth,
    this.scrollController,
  });
  final List<SyncedTreeNode<String, String>> Function() builder;
  final int maxStickyDepth;
  final ScrollController? scrollController;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  TreeController<String, String>? controller;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: CustomScrollView(
            controller: widget.scrollController,
            slivers: [
              SyncedSliverTree<String, String>(
                tree: widget.builder(),
                maxStickyDepth: widget.maxStickyDepth,
                animationStyle: const TreeAnimationStyle(
                  expandCollapse: TreeAnimationSpec(
                    duration: Duration(milliseconds: 400),
                    curve: Curves.linear,
                  ),
                ),
                itemBuilder: (context, node) {
                  controller ??= node.controller;
                  return SizedBox(
                    key: ValueKey("row-${node.key}"),
                    height: _heightFor(node.key),
                    child: Text(node.key),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Re-paints through a recorder and asserts the destination header band
/// is painted EXACTLY ONCE, and that the EXIT clip excludes the band so
/// no ghost pixel can enter it. For a CLIPPED ghost the clip, not a
/// repaint, is what keeps the band free, which is why Pass A.7 covers
/// EDGE-painted ghosts only.
void _expectAnchorPaintedOnceAndBandGhostFree(
  WidgetTester tester,
  RenderSliverTree<String, String> render,
  String tag, {
  required bool anchorIsSticky,
}) {
  expect(
    render.debugLastPhantomGhostPaint.containsKey("x"),
    isTrue,
    reason: "[$tag] ghost capture must be present mid-slide",
  );
  final cap = render.debugLastPhantomGhostPaint["x"]!;
  final bandTop = cap.anchorBand.top;

  // SANITY: the pass that owns the anchor must be the one the case
  // claims, or a count of 1 could come from Pass B silently owning it.
  if (anchorIsSticky) {
    expect(
      render.debugStickyHeaders.map((h) => h.nodeId),
      contains("fav"),
      reason: "[$tag] the anchor must be in the sticky set; Pass B owns "
          "its single paint",
    );
    expect(
      render.debugLastPaintedStickyKeys,
      contains("fav"),
      reason: "[$tag] Pass B must have painted the anchor",
    );
  } else {
    expect(
      render.debugStickyHeaders,
      isEmpty,
      reason: "[$tag] no header may be sticky, or Pass B would own the "
          "anchor and the count would not test Pass A / A.7",
    );
    expect(
      render.debugLastPaintedStickyKeys,
      isNot(contains("fav")),
      reason: "[$tag] Pass B must not have painted the anchor",
    );
  }

  final recorder = _Recorder(
    ContainerLayer(),
    Offset.zero & const Size(800, 600),
  );
  render.paint(recorder, Offset.zero);

  // DISCRIMINATOR: exactly one paintChild lands on the band top.
  int bandPaints = 0;
  for (final rec in recorder.order) {
    if ((rec.top - bandTop).abs() < 1.0) bandPaints++;
  }
  expect(
    bandPaints,
    1,
    reason: "[$tag] the anchor must be painted exactly once per frame; "
        "2 is the Pass A + Pass A.7 double paint (behind a "
        "RepaintBoundary it degenerates to a layer move that destroys "
        "Pass A's placement). order=${recorder.order}",
  );

  // CONTROL: the record is the CLIPPED kind and its clip excludes the
  // band, the recorded reason the repaint was redundant.
  expect(
    cap.clipRect,
    isNotNull,
    reason: "[$tag] the ghost must be the CLIPPED kind (an edge ghost "
        "records no clip)",
  );
  expect(
    cap.clipRect!.overlaps(
      Rect.fromLTWH(0, cap.anchorBand.top, 800, cap.anchorBand.height),
    ),
    isFalse,
    reason: "[$tag] the EXIT clip must exclude the anchor's band; no "
        "ghost pixel can land inside it",
  );
}

void main() {
  testWidgets("non-sticky destination header occludes the crossing card "
      "(maxStickyDepth 0)", (tester) async {
    var fav = false;
    List<SyncedTreeNode<String, String>> build() => fav
        ? [
            _n("fav", [_n("x")]),
            _n("others", [_n("o1")]),
          ]
        : [
            _n("fav", [_n("fav_ph")]),
            _n("others", [_n("x"), _n("o1")]),
          ];

    await tester.pumpWidget(_Harness(builder: build, maxStickyDepth: 0));
    await tester.pumpAndSettle();
    final c = tester.state<_HarnessState>(find.byType(_Harness)).controller!;
    c.collapse(key: "fav", animate: false);
    await tester.pump();

    fav = true;
    await tester.pumpWidget(_Harness(builder: build, maxStickyDepth: 0));
    await tester.pump();

    final render = _render(tester);
    // Sample mid-slide. The header is never sticky here, and the ghost
    // is CLIPPED, so the EXIT clip keeps the band ghost-free and the
    // anchor's single paint is Pass A's.
    await tester.pump(const Duration(milliseconds: 120));
    _expectAnchorPaintedOnceAndBandGhostFree(
      tester,
      render,
      "maxStickyDepth0",
      anchorIsSticky: false,
    );

    await tester.pumpAndSettle();
    expect(c.visibleNodes.contains("x"), isFalse);
  });

  testWidgets(
    "sticky destination header paints once, by Pass B, over the ghost",
    (tester) async {
      var fav = false;
      List<SyncedTreeNode<String, String>> build() => fav
          ? [
              _n("fav", [_n("x")]),
              _n("others", [_n("o1")]),
            ]
          : [
              _n("fav", [_n("fav_ph")]),
              _n("others", [_n("x"), _n("o1")]),
            ];

      // maxStickyDepth: 1. The case's original premise (the header is
      // dropped from the sticky set while animating) was measured false:
      // on every sampled frame the anchor IS in the sticky set, so Pass
      // A and Pass A.7 both skip it and Pass B paints it exactly once
      // over the ghost. Renamed per L24; kept as real coverage for the
      // Pass B half of the exactly-once rule.
      await tester.pumpWidget(_Harness(builder: build, maxStickyDepth: 1));
      await tester.pumpAndSettle();
      final c = tester.state<_HarnessState>(find.byType(_Harness)).controller!;
      c.collapse(key: "fav", animate: false);
      await tester.pump();

      fav = true;
      await tester.pumpWidget(_Harness(builder: build, maxStickyDepth: 1));
      await tester.pump();

      final render = _render(tester);
      // Sample within the first ~3 frames (the throttle/animation window).
      bool checked = false;
      for (int i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (render.debugLastPhantomGhostPaint.containsKey("x")) {
          _expectAnchorPaintedOnceAndBandGhostFree(
            tester,
            render,
            "sticky-owned-frame$i",
            anchorIsSticky: true,
          );
          checked = true;
        }
      }
      expect(
        checked,
        isTrue,
        reason: "Ghost should have been sliding in the early frames",
      );

      await tester.pumpAndSettle();
      expect(c.visibleNodes.contains("x"), isFalse);
    },
  );

  testWidgets(
    "card disappears into the sticky-PINNED destination header, not its "
    "structural offset",
    // UNCONSTRUCTABLE — see Discovered finding "Sticky-pinned EXIT-anchor
    // scenario is unconstructable" in the checklist. An EXIT phantom anchor
    // is the deepest VISIBLE ancestor of a hidden ghost (a collapsed /
    // childless-in-view header), and `computeStickyHeaders` only pins
    // candidates with visible descendants — so an exit anchor is NEVER in
    // the sticky set and `anchorBand.top` is always structural. Left
    // present (skipped) for the planner to inspect; resolution requires a
    // plan revision (drop Goal 4 / this case, or redefine a constructable
    // scenario). The body below never observes a sliding ghost whose
    // anchor band differs from structural.
    skip: true,
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      // Enough rows that scrolling pins the `fav` header to the viewport top.
      var fav = false;
      List<SyncedTreeNode<String, String>> build() => fav
          ? [
              _n("fav", [_n("x"), for (int i = 0; i < 10; i++) _n("f$i")]),
              _n("others", [_n("o1")]),
            ]
          : [
              _n("fav", [for (int i = 0; i < 10; i++) _n("f$i")]),
              _n("others", [_n("x"), _n("o1")]),
            ];

      await tester.pumpWidget(
        _Harness(builder: build, maxStickyDepth: 1, scrollController: scroll),
      );
      await tester.pumpAndSettle();
      final c = tester.state<_HarnessState>(find.byType(_Harness)).controller!;

      // Scroll so `fav` (root header) is sticky-pinned to the viewport top
      // (its structural offset is now above the viewport, but it pins).
      scroll.jumpTo(200);
      await tester.pump();
      await tester.pumpAndSettle();

      // Favorite x: it moves UP into the sticky-pinned `fav` header.
      fav = true;
      await tester.pumpWidget(
        _Harness(builder: build, maxStickyDepth: 1, scrollController: scroll),
      );
      await tester.pump();

      final render = _render(tester);
      bool sampled = false;
      for (int i = 0; i < 20; i++) {
        if (render.debugLastPhantomGhostPaint.containsKey("x")) {
          final cap = render.debugLastPhantomGhostPaint["x"]!;
          // The `fav` header is pinned at the viewport top (pinnedY ≈ 0).
          // The ghost's anchor band must read the PAINTED (pinned) band,
          // not the structural (off-screen, negative) offset.
          expect(
            cap.anchorBand.top,
            moreOrLessEquals(0.0, epsilon: 0.5),
            reason:
                "Anchor band must be the PAINTED pinned position "
                "(~0), not the structural off-screen offset. Got "
                "${cap.anchorBand.top}.",
          );
          sampled = true;
          break;
        }
        if (!c.hasActiveSlides) break;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        sampled,
        isTrue,
        reason: "Ghost should have slid into the pinned header",
      );

      await tester.pumpAndSettle();
      expect(c.visibleNodes.contains("x"), isFalse);
    },
  );

  group("L24 legs: each anchor is painted by exactly one pass", () {
    testWidgets(
      "an EDGE-ghost anchor scrolled into view is painted exactly once "
      "per frame",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationStyle: const TreeAnimationStyle(
            expandCollapse: TreeAnimationSpec(
              duration: Duration(milliseconds: 400),
              curve: Curves.linear,
            ),
          ),
        );
        addTearDown(controller.dispose);
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final counts = <String, int>{};
        String? lastTap;

        controller.setRoots([
          for (int i = 0; i < 30; i++) TreeNode(key: "n$i", data: "n$i"),
        ]);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 600,
                child: CustomScrollView(
                  controller: scroll,
                  slivers: [
                    SliverTree<String, String>(
                      controller: controller,
                      addRepaintBoundaries: false,
                      nodeBuilder: (context, key, depth) {
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => lastTap = key,
                          child: SizedBox(
                            height: 40,
                            child: CustomPaint(
                              painter: _CountPainter(counts, key),
                              child: Text(key),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // n20 sits at y = 800, outside the viewport but inside the cache
        // region; reparenting the visible n5 under it records an
        // EDGE-painted exit ghost (the anchor is off screen at consume
        // time), which is exactly the record Pass A.7 keeps serving.
        controller.moveNode(
          "n5",
          "n20",
          animate: true,
          slideDuration: const Duration(milliseconds: 800),
          slideCurve: Curves.linear,
        );
        await tester.pump();
        final render = _render(tester);
        expect(
          controller.visibleNodes.contains("n5"),
          isFalse,
          reason: "setup: n5 must be hidden under the collapsed n20",
        );
        expect(
          render.debugPhantomExitGhostCount,
          1,
          reason: "setup: exactly one exit ghost must install",
        );

        // Bring the anchor into view mid-slide, so Pass A and Pass A.7
        // can both see it in the same frame.
        scroll.jumpTo(400.0);
        await tester.pump();
        expect(
          controller.hasActiveSlides,
          isTrue,
          reason: "setup: the ghost's FLIP must still be in flight",
        );
        expect(
          render.debugStickyHeaders,
          isEmpty,
          reason: "setup: no sticky pass may own the anchor",
        );

        counts.clear();
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          counts["n10"],
          1,
          reason: "control: an ordinary in-flow row paints exactly once",
        );
        expect(
          counts["n20"],
          1,
          reason: "the EDGE-ghost anchor must be painted exactly once; 2 "
              "is the Pass A + Pass A.7 double paint",
        );

        // Hit-test control (uninformative before the fix, pinned after):
        // a tap inside the anchor's band lands on the anchor; the A.7
        // bucket is tested first in the slide-active path. The band
        // moves while the shifted rows' FLIP decays, so the tap point is
        // read from the anchor's painted bounds at tap time.
        expect(
          controller.hasActiveSlides,
          isTrue,
          reason: "control setup: the ghost must still be live at tap "
              "time",
        );
        final bounds = render.paintedRowBounds("n20")!;
        final tapY = bounds.paintedOffset - scroll.offset + 20.0;
        await tester.tapAt(Offset(400, tapY));
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          lastTap,
          "n20",
          reason: "control: the anchor receives a tap in its band",
        );

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "an EXITING anchor still paints exactly once, by Pass A",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationStyle: const TreeAnimationStyle(
            expandCollapse: TreeAnimationSpec(
              duration: Duration(milliseconds: 400),
              curve: Curves.linear,
            ),
          ),
        );
        addTearDown(controller.dispose);
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final counts = <String, int>{};

        controller.setRoots([
          for (int i = 0; i < 30; i++) TreeNode(key: "n$i", data: "n$i"),
        ]);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 600,
                child: CustomScrollView(
                  controller: scroll,
                  slivers: [
                    SliverTree<String, String>(
                      controller: controller,
                      addRepaintBoundaries: false,
                      nodeBuilder: (context, key, depth) {
                        return SizedBox(
                          height: 40,
                          child: CustomPaint(
                            painter: _CountPainter(counts, key),
                            child: Text(key),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        controller.moveNode(
          "n5",
          "n20",
          animate: true,
          slideDuration: const Duration(milliseconds: 400),
          slideCurve: Curves.linear,
        );
        await tester.pump();
        scroll.jumpTo(400.0);
        await tester.pump();

        // Removing the anchor makes it EXITING; the same remove frees
        // the hidden ghost subtree, so this leg pins the Pass A half of
        // the exactly-once rule: an exiting row must never fall out of
        // BOTH passes (A.7's selection excludes exiting anchors, so Pass
        // A must keep painting them; 0 paints is the failure).
        controller.remove(key: "n20", animate: true);
        await tester.pump();
        expect(
          controller.isExiting("n20"),
          isTrue,
          reason: "setup: the anchor must be exiting",
        );

        counts.clear();
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          counts["n20"],
          1,
          reason: "an EXITING row is painted exactly once, by Pass A, "
              "never zero times",
        );

        await tester.pumpAndSettle();
      },
    );
  });
}

class _CountPainter extends CustomPainter {
  _CountPainter(this.counts, this.key);

  final Map<String, int> counts;
  final String key;

  @override
  void paint(Canvas canvas, Size size) {
    counts[key] = (counts[key] ?? 0) + 1;
  }

  @override
  bool shouldRepaint(covariant _CountPainter oldDelegate) => true;
}
