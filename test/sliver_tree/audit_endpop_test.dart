/// Last-sliding-frame END-POP oracle (promoted from `audit_endpop_probe.dart`).
///
/// The 0.0.23 occlusion oracle (`repro_occlusion_tall_card_test.dart`) only
/// asserts the FAR side of the destination header band converges. A card
/// TALLER than its destination collapsed header, reparented UPWARD into a
/// collapsed TOP section (favorite), left `(cardExtent − headerExtent) ≈
/// 32px` visible on the TRAILING side on the LAST sliding frame, then prune
/// hid it — a one-frame POP. This file adds the hard last-sliding-frame
/// assertion the 0.0.23 oracle lacked, counting BOTH sides outside the band.
///
/// MEASURE: `_userVisible` = (ghostRect ∩ clipRect) with the band region
/// (covered on top by the header repaint) removed, counting both ABOVE and
/// BELOW the band. On the last sliding frame this must be < 2px in BOTH
/// directions. The slide is sampled at a FINE step (`_kStepMs` = 4ms, well
/// below the 60Hz 16ms frame) so the last sampled frame is genuinely on the
/// final approach: a coarse 16ms step over the longer UPWARD-with-tuck
/// travel can sample one whole step (~5px) short of settle even though
/// convergence is perfectly linear to ~0 — that is a sampling artifact, not
/// an end-pop. Invariant 8: the capture is EMPTY at settle, so every read
/// `containsKey`-guards and the settle frame asserts key-ABSENCE.
library;

import 'package:widgets_extended/sliver_tree/animation_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/render_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree_widget.dart';
import 'package:widgets_extended/sliver_tree/synced_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/synced_tree_node.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';

const double _kHeader = 48.0;
const double _kCard = 80.0;
const double _kPlaceholder = 60.0;

/// Fine per-frame sample step. Below the 16ms 60Hz frame so the last sampled
/// sliding frame lands on the true final approach (residual < 2px), not one
/// coarse step short of settle. See the file-level MEASURE note.
const Duration _kStep = Duration(milliseconds: 4);

SyncedTreeNode<String, String> _n(String k,
        [List<SyncedTreeNode<String, String>>? c]) =>
    SyncedTreeNode(key: k, data: k, children: c ?? const []);

RenderSliverTree<String, String> _render(WidgetTester t) =>
    t.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>));

class _Harness extends StatefulWidget {
  const _Harness({required this.builder, required this.cardHeight});
  final List<SyncedTreeNode<String, String>> Function() builder;
  final double cardHeight;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  TreeController<String, String>? controller;

  double _heightFor(String k) {
    if (k == "fav" || k == "others") return _kHeader;
    if (k == "fav_ph" || k == "others_ph") return _kPlaceholder;
    return widget.cardHeight; // the moved card "x" (and siblings)
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: CustomScrollView(slivers: [
            SyncedSliverTree<String, String>(
              tree: widget.builder(),
              maxStickyDepth: 1,
              animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 400), curve: Curves.linear)),
              itemBuilder: (context, node) {
                controller ??= node.controller;
                return SizedBox(
                    key: ValueKey("row-${node.key}"),
                    height: _heightFor(node.key),
                    child: Text(node.key));
              },
            ),
          ]),
        ),
      );
}

/// User-visible card extent this frame = (ghostRect ∩ clipRect) with the
/// band region (covered on top by the header repaint) subtracted, counting
/// BOTH sides outside the band. Returns -1 if no capture (no sliding ghost).
/// MUST be read only via `containsKey` semantics (returns -1 when absent).
double _userVisible(RenderSliverTree<String, String> r) {
  if (!r.debugLastPhantomGhostPaint.containsKey("x")) return -1;
  final cap = r.debugLastPhantomGhostPaint["x"]!;
  final clipped = cap.clipRect == null
      ? cap.ghostRect
      : cap.ghostRect.intersect(cap.clipRect!);
  if (clipped.height <= 0) return 0;
  final band = cap.anchorBand;
  final above = (band.top - clipped.top).clamp(0.0, clipped.height);
  final below = (clipped.bottom - band.bottom).clamp(0.0, clipped.height);
  return above + below; // visible parts outside the band, both sides
}

/// Asserts the visible-residual sequence shows NO end-pop: once it has begun
/// to settle (entered the final approach), it never JUMPS back UP. A genuine
/// end-pop (trailing region re-exposed because the clip used the wrong side)
/// appears as a large upward step in the residual on the final frames. Small
/// float noise is tolerated; a re-exposure is many px.
void _expectNoPop(List<double> vis) {
  for (int i = 1; i < vis.length; i++) {
    final jump = vis[i] - vis[i - 1];
    expect(jump, lessThan(2.0),
        reason: "end-pop: visible residual jumped UP by ${jump}px at frame $i "
            "(sequence ...${vis.sublist((i - 2).clamp(0, vis.length), i + 1)}) "
            "— the trailing region was re-exposed");
  }
}

/// Drives the reparent slide. `favorite=true`: x slides UP into the
/// collapsed TOP `fav` section (body-side approach ⇒ tuck). `favorite=false`:
/// x slides DOWN into the collapsed BOTTOM `others` section (no tuck).
/// Returns the per-frame `_userVisible` samples (only frames where the ghost
/// was actually sliding).
Future<List<double>> _drive(
  WidgetTester tester, {
  required bool favorite,
  double cardHeight = _kCard,
}) async {
  var moved = false;
  List<SyncedTreeNode<String, String>> build() {
    if (favorite) {
      return moved
          ? [_n("fav", [_n("x")]), _n("others", [_n("o1")])]
          : [_n("fav", [_n("fav_ph")]), _n("others", [_n("x"), _n("o1")])];
    } else {
      return moved
          ? [_n("fav", [_n("fav_ph")]), _n("others", [_n("x"), _n("o1")])]
          : [_n("fav", [_n("x")]), _n("others", [_n("o1")])];
    }
  }

  await tester
      .pumpWidget(_Harness(builder: build, cardHeight: cardHeight));
  await tester.pumpAndSettle();
  final c = tester.state<_HarnessState>(find.byType(_Harness)).controller!;
  c.collapse(key: favorite ? "fav" : "others", animate: false);
  await tester.pump();
  moved = true;
  await tester
      .pumpWidget(_Harness(builder: build, cardHeight: cardHeight));
  await tester.pump();
  final r = _render(tester);
  final vis = <double>[];
  // ~400ms slide sampled at 4ms ⇒ up to ~110 frames; cap well above that.
  for (int i = 0; i < 200; i++) {
    final v = _userVisible(r);
    if (v >= 0) vis.add(v);
    if (!c.hasActiveSlides) break;
    await tester.pump(_kStep);
  }
  await tester.pumpAndSettle();
  return vis;
}

void main() {
  testWidgets(
    "FAVORITE/up: last sliding frame visible-outside-band < 2px (both sides)",
    (tester) async {
      final vis = await _drive(tester, favorite: true);
      expect(vis, isNotEmpty,
          reason: "ghost must have actually slid (capture populated)");
      // No END-POP: the visible residual converges to ~0 with no upward jump.
      // Pre-fix the trailing region was never clipped, so the residual stayed
      // ~32px (= cardExtent − headerExtent) on the final sliding frames.
      _expectNoPop(vis);
      final lastVisible = vis.last;
      expect(lastVisible, lessThan(2.0),
          reason: "tall card left ${lastVisible}px visible OUTSIDE the band on "
              "the last sliding frame — the end-pop the audit measured at ~36px");
    },
  );

  testWidgets(
    "UNFAVORITE/down: last sliding frame visible-outside-band stays < 2px",
    (tester) async {
      final vis = await _drive(tester, favorite: false);
      expect(vis, isNotEmpty,
          reason: "ghost must have actually slid (capture populated)");
      _expectNoPop(vis);
      final lastVisible = vis.last;
      expect(lastVisible, lessThan(2.0),
          reason: "DOWNWARD must not regress (today ~1.9px); got ${lastVisible}px");
    },
  );

  testWidgets(
    "FAVORITE/up: card bottom reaches band bottom before prune",
    (tester) async {
      var moved = false;
      List<SyncedTreeNode<String, String>> build() => moved
          ? [_n("fav", [_n("x")]), _n("others", [_n("o1")])]
          : [_n("fav", [_n("fav_ph")]), _n("others", [_n("x"), _n("o1")])];

      await tester
          .pumpWidget(_Harness(builder: build, cardHeight: _kCard));
      await tester.pumpAndSettle();
      final c =
          tester.state<_HarnessState>(find.byType(_Harness)).controller!;
      c.collapse(key: "fav", animate: false);
      await tester.pump();
      moved = true;
      await tester
          .pumpWidget(_Harness(builder: build, cardHeight: _kCard));
      await tester.pump();

      final r = _render(tester);
      // Capture the LAST sliding frame's clipped-ghost bottom vs band bottom.
      double? lastBottomDelta;
      for (int i = 0; i < 200; i++) {
        if (r.debugLastPhantomGhostPaint.containsKey("x")) {
          final cap = r.debugLastPhantomGhostPaint["x"]!;
          final clipped = cap.clipRect == null
              ? cap.ghostRect
              : cap.ghostRect.intersect(cap.clipRect!);
          // The clipped ghost's bottom must converge on the band bottom: the
          // card has fully tucked behind the header.
          lastBottomDelta = (clipped.bottom - cap.anchorBand.bottom).abs();
        }
        if (!c.hasActiveSlides) break;
        await tester.pump(_kStep);
      }
      expect(lastBottomDelta, isNotNull,
          reason: "ghost must have slid (capture populated)");
      expect(lastBottomDelta!, lessThan(2.0),
          reason: "clipped ghost bottom must reach the band bottom (full "
              "convergence) before prune; off by ${lastBottomDelta}px");

      // After settle the ghost is pruned (Invariant 8) and x is hidden.
      await tester.pumpAndSettle();
      expect(r.debugLastPhantomGhostPaint.containsKey("x"), isFalse,
          reason: "capture must be gone at settle (ghost pruned)");
      expect(c.visibleNodes.contains("x"), isFalse,
          reason: "card must be fully hidden inside the collapsed section");
    },
  );

  testWidgets(
    "FAVORITE/up: no t=0 jump — first painted top equals pre-move baseline",
    (tester) async {
      var moved = false;
      List<SyncedTreeNode<String, String>> build() => moved
          ? [_n("fav", [_n("x")]), _n("others", [_n("o1")])]
          : [_n("fav", [_n("fav_ph")]), _n("others", [_n("x"), _n("o1")])];

      await tester
          .pumpWidget(_Harness(builder: build, cardHeight: _kCard));
      await tester.pumpAndSettle();
      final c =
          tester.state<_HarnessState>(find.byType(_Harness)).controller!;
      c.collapse(key: "fav", animate: false);
      await tester.pump();

      // Pre-move: x is visible in `others`. Record its painted top — the FLIP
      // "before". Visible order (fav collapsed): fav(48), others(48), x(80).
      final preMoveTop = tester.getTopLeft(find.byKey(const ValueKey("row-x"))).dy;

      moved = true;
      await tester
          .pumpWidget(_Harness(builder: build, cardHeight: _kCard));
      await tester.pump();

      // FIRST sliding frame: the ghost's painted top must equal the pre-move
      // baseline (no t=0 jump). If only ONE of the two tuck sites was changed
      // (I-AGREE / the TRAP violated), paintedY != baseline.y and this fails.
      final r = _render(tester);
      expect(r.debugLastPhantomGhostPaint.containsKey("x"), isTrue,
          reason: "ghost should be sliding on the first post-move frame");
      final firstTop = r.debugLastPhantomGhostPaint["x"]!.ghostRect.top;
      expect((firstTop - preMoveTop).abs(), lessThan(2.0),
          reason: "first sliding frame ghost top $firstTop diverged from the "
              "pre-move baseline $preMoveTop — a t=0 jump (one tuck site "
              "missing the other)");

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "EQUAL-height up: tuck is zero, slide distance unchanged",
    (tester) async {
      // card == header == 48 ⇒ tuck = max(0, 48 − 48) = 0. The installed
      // slide delta must equal the pure geometric distance with NO extra.
      var moved = false;
      List<SyncedTreeNode<String, String>> build() => moved
          ? [_n("fav", [_n("x")]), _n("others", [_n("o1")])]
          : [_n("fav", [_n("fav_ph")]), _n("others", [_n("x"), _n("o1")])];

      await tester
          .pumpWidget(_Harness(builder: build, cardHeight: _kHeader));
      await tester.pumpAndSettle();
      final c =
          tester.state<_HarnessState>(find.byType(_Harness)).controller!;
      c.collapse(key: "fav", animate: false);
      await tester.pump();

      // Pre-move baseline top of x and the settled destination header (fav)
      // top. fav is the TOP section ⇒ settled top = 0. The no-tuck distance
      // is `preMoveTop − 0`; `getSlideDelta` for an UPWARD slide is the
      // positive magnitude `baseline.y − settledAnchorY`.
      final preMoveTop = tester.getTopLeft(find.byKey(const ValueKey("row-x"))).dy;

      moved = true;
      await tester
          .pumpWidget(_Harness(builder: build, cardHeight: _kHeader));
      await tester.pump();

      expect(c.hasActiveSlides, isTrue);
      // tuck == 0 ⇒ installed delta is exactly the geometric distance (no
      // +32 over-travel). If a tuck were wrongly applied at equal height the
      // delta would be off by the tuck amount.
      expect(c.getSlideDelta("x"), moreOrLessEquals(preMoveTop, epsilon: 0.5),
          reason: "equal-height slide distance must be the pure geometric "
              "distance $preMoveTop (tuck 0)");

      // And the slide still converges with nothing left outside the band.
      final r = _render(tester);
      double last = -1;
      for (int i = 0; i < 200; i++) {
        final v = _userVisible(r);
        if (v >= 0) last = v;
        if (!c.hasActiveSlides) break;
        await tester.pump(_kStep);
      }
      expect(last, lessThan(2.0),
          reason: "equal-height card must converge fully (got ${last}px)");
      await tester.pumpAndSettle();
      expect(c.visibleNodes.contains("x"), isFalse);
    },
  );
}
