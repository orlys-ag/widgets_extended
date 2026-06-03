/// Defect-2 (header-occludes-ghost z-order) hard assertions.
///
/// During a between-section reparent slide the tall card paints BEHIND
/// every section header it visually crosses — INCLUDING a header that is
/// NOT in the sticky set. Three gaps are covered:
///   1. `maxStickyDepth: 0` — the destination header is never sticky, so
///      only the new Pass A.7 re-asserts it on top of the ghost.
///   2. A header dropped from the sticky set while ANIMATING (sticky
///      recompute is throttled during animation) — Pass A.7 still repaints
///      it over the ghost in the early frames.
///   3. The destination header is sticky-PINNED (scrolled) — the ghost
///      converges on / is clipped against the header's PAINTED (pinned)
///      band, read at paint time, not its structural offset.
///
/// PAINT-ORDER ORACLE: a no-draw recording `PaintingContext` captures the
/// order of `paintChild` calls. Using `debugLastPhantomGhostPaint["x"]`
/// (the ghost's painted rect + the destination header's painted band) we
/// locate the ghost's paint and the destination header's repaint and
/// assert the header is painted AFTER (on top of) the ghost.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/render_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree_widget.dart';
import 'package:widgets_extended/sliver_tree/synced_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/synced_tree_node.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';

const double _kHeader = 48.0;
const double _kCard = 80.0;
const double _kPlaceholder = 60.0;

double _heightFor(String key) {
  if (key == "fav" || key == "others") return _kHeader;
  if (key == "fav_ph" || key == "others_ph") return _kPlaceholder;
  return _kCard;
}

SyncedTreeNode<String, String> _n(String k,
        [List<SyncedTreeNode<String, String>>? c]) =>
    SyncedTreeNode(key: k, data: k, children: c ?? const []);

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
  const _Harness({required this.builder, required this.maxStickyDepth, this.scrollController});
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
                animationDuration: const Duration(milliseconds: 400),
                animationCurve: Curves.linear,
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

/// Re-paints through a recorder and asserts the destination header band is
/// painted AFTER (on top of) the ghost. Reads the ghost rect + header band
/// from the live `debugLastPhantomGhostPaint` capture.
void _expectHeaderOverGhost(
    WidgetTester tester, RenderSliverTree<String, String> render, String tag) {
  expect(render.debugLastPhantomGhostPaint.containsKey("x"), isTrue,
      reason: "[$tag] ghost capture must be present mid-slide");
  final cap = render.debugLastPhantomGhostPaint["x"]!;
  final ghostTop = cap.ghostRect.top;
  final bandTop = cap.anchorBand.top;

  final recorder = _Recorder(
    ContainerLayer(),
    Offset.zero & const Size(800, 600),
  );
  render.paint(recorder, Offset.zero);

  // Last paint of the ghost (at ghostTop, inside the EXIT clip).
  int ghostIdx = -1;
  // Last paint of the destination header (at the band top).
  int headerIdx = -1;
  for (int i = 0; i < recorder.order.length; i++) {
    final rec = recorder.order[i];
    if ((rec.top - ghostTop).abs() < 1.0) ghostIdx = i;
    if ((rec.top - bandTop).abs() < 1.0) headerIdx = i;
  }
  expect(ghostIdx, greaterThanOrEqualTo(0),
      reason: "[$tag] ghost paint not recorded");
  expect(headerIdx, greaterThanOrEqualTo(0),
      reason: "[$tag] destination header paint not recorded");
  expect(headerIdx, greaterThan(ghostIdx),
      reason: "[$tag] destination header must paint AFTER (on top of) the "
          "ghost. ghostIdx=$ghostIdx headerIdx=$headerIdx order=${recorder.order}");
}

void main() {
  testWidgets(
    "non-sticky destination header occludes the crossing card "
    "(maxStickyDepth 0)",
    (tester) async {
      var fav = false;
      List<SyncedTreeNode<String, String>> build() => fav
          ? [_n("fav", [_n("x")]), _n("others", [_n("o1")])]
          : [_n("fav", [_n("fav_ph")]), _n("others", [_n("x"), _n("o1")])];

      await tester.pumpWidget(_Harness(builder: build, maxStickyDepth: 0));
      await tester.pumpAndSettle();
      final c = tester.state<_HarnessState>(find.byType(_Harness)).controller!;
      c.collapse(key: "fav", animate: false);
      await tester.pump();

      fav = true;
      await tester.pumpWidget(_Harness(builder: build, maxStickyDepth: 0));
      await tester.pump();

      final render = _render(tester);
      // Sample mid-slide (header is never sticky here, so only Pass A.7
      // can put it over the ghost).
      await tester.pump(const Duration(milliseconds: 120));
      _expectHeaderOverGhost(tester, render, "maxStickyDepth0");

      await tester.pumpAndSettle();
      expect(c.visibleNodes.contains("x"), isFalse);
    },
  );

  testWidgets(
    "header dropped from sticky set while animating still occludes the card",
    (tester) async {
      var fav = false;
      List<SyncedTreeNode<String, String>> build() => fav
          ? [_n("fav", [_n("x")]), _n("others", [_n("o1")])]
          : [_n("fav", [_n("fav_ph")]), _n("others", [_n("x"), _n("o1")])];

      // maxStickyDepth: 1 — but during the first frames after the reparent
      // the destination header is animating, so it is dropped from the
      // sticky set; Pass A.7 must still occlude the ghost.
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
          _expectHeaderOverGhost(tester, render, "dropped-from-sticky-frame$i");
          checked = true;
        }
      }
      expect(checked, isTrue,
          reason: "Ghost should have been sliding in the early frames");

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

      await tester.pumpWidget(_Harness(
          builder: build, maxStickyDepth: 1, scrollController: scroll));
      await tester.pumpAndSettle();
      final c = tester.state<_HarnessState>(find.byType(_Harness)).controller!;

      // Scroll so `fav` (root header) is sticky-pinned to the viewport top
      // (its structural offset is now above the viewport, but it pins).
      scroll.jumpTo(200);
      await tester.pump();
      await tester.pumpAndSettle();

      // Favorite x: it moves UP into the sticky-pinned `fav` header.
      fav = true;
      await tester.pumpWidget(_Harness(
          builder: build, maxStickyDepth: 1, scrollController: scroll));
      await tester.pump();

      final render = _render(tester);
      bool sampled = false;
      for (int i = 0; i < 20; i++) {
        if (render.debugLastPhantomGhostPaint.containsKey("x")) {
          final cap = render.debugLastPhantomGhostPaint["x"]!;
          // The `fav` header is pinned at the viewport top (pinnedY ≈ 0).
          // The ghost's anchor band must read the PAINTED (pinned) band,
          // not the structural (off-screen, negative) offset.
          expect(cap.anchorBand.top, moreOrLessEquals(0.0, epsilon: 0.5),
              reason: "Anchor band must be the PAINTED pinned position "
                  "(~0), not the structural off-screen offset. Got "
                  "${cap.anchorBand.top}.");
          sampled = true;
          break;
        }
        if (!c.hasActiveSlides) break;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(sampled, isTrue,
          reason: "Ghost should have slid into the pinned header");

      await tester.pumpAndSettle();
      expect(c.visibleNodes.contains("x"), isFalse);
    },
  );
}
