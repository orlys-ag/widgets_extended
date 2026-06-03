/// Defect-1 (far-overhang occlusion) hard assertions, promoted from
/// `repro_occlusion_tall_card.dart`.
///
/// A card (80px) is TALLER than its destination collapsed header (48px).
/// When reparented INTO the collapsed section it slides toward the header
/// and must DISAPPEAR behind it. The OLD half-plane clip left
/// `(cardHeight - headerHeight) = 32px` of card visible PAST the header
/// on the far side. The fix (EXIT-role band clip + header repaint) kills
/// the far overhang.
///
/// ORACLE — TRANSIT-aware, measured against the ACTUAL clip the render
/// produced this frame (`RenderSliverTree.debugLastPhantomGhostPaint`),
/// NOT re-derived from `getSlideDelta` (which is clip-insensitive at
/// settle). Per the plan's Testing Plan:
///   * PER-FRAME (ghost still sliding, capture key PRESENT): zero ghost
///     pixels on the FAR side of the destination header band. The
///     TRAILING side (mid-travel) is legitimately visible and is NOT
///     asserted to zero.
///   * SETTLE (capture key ABSENT — ghost pruned, Invariant 8): the LAST
///     sliding frame's FAR-side residual had converged (`< 0.5`), the
///     capture key is gone, AND the card is not in `visibleNodes`. The
///     settle oracle MUST NOT non-null-deref the (empty) capture.
library;

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

class _Harness extends StatefulWidget {
  const _Harness({required this.builder});
  final List<SyncedTreeNode<String, String>> Function() builder;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  TreeController<String, String>? controller;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SyncedSliverTree<String, String>(
              tree: widget.builder(),
              maxStickyDepth: 1,
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
    );
  }
}

/// The visible FAR-side residual of the ghost this frame, in px. The FAR
/// side is the one PAST the header into the collapsed body (the defect
/// side); the TRAILING side (mid-travel) is legitimately visible.
///
///  * `slidUp` (card came from BELOW, slid UP into the band): FAR = ABOVE
///    the band top.
///  * `!slidUp` (card came from ABOVE, slid DOWN into the band): FAR =
///    BELOW the band bottom.
///
/// MUST be called only inside a `containsKey` guard (Invariant 8 — the
/// capture is empty at settle).
double _farSideVisible(
    RenderSliverTree<String, String> render, String key, bool slidUp) {
  final cap = render.debugLastPhantomGhostPaint[key]!; // safe: key checked
  final clipped =
      cap.clipRect == null ? cap.ghostRect : cap.ghostRect.intersect(cap.clipRect!);
  if (clipped.height <= 0) return 0.0;
  final bandTop = cap.anchorBand.top;
  final bandBottom = cap.anchorBand.bottom;
  final residualAbove = (bandTop - clipped.top).clamp(0.0, clipped.height);
  final residualBelow = (clipped.bottom - bandBottom).clamp(0.0, clipped.height);
  return slidUp ? residualAbove : residualBelow;
}

void main() {
  testWidgets(
    "FAVORITE: tall card slides UP, FAR side occluded per-frame, "
    "fully occluded at settle",
    (tester) async {
      var fav = false; // false = x in others; true = x favorited (in fav)
      List<SyncedTreeNode<String, String>> build() => fav
          ? [_n("fav", [_n("x")]), _n("others", [_n("o1")])]
          : [_n("fav", [_n("fav_ph")]), _n("others", [_n("x"), _n("o1")])];

      await tester.pumpWidget(_Harness(builder: build));
      await tester.pumpAndSettle();
      final c = tester.state<_HarnessState>(find.byType(_Harness)).controller!;

      // Collapse favorites (the destination), keep others expanded with x.
      c.collapse(key: "fav", animate: false);
      await tester.pump();

      // Favorite x: x moves from others (visible) UP into collapsed fav (top).
      fav = true;
      await tester.pumpWidget(_Harness(builder: build));
      await tester.pump();

      final render = _render(tester);
      double? lastFarSide;

      // PER-FRAME loop: pump in 16ms steps, assert FAR side == 0 while the
      // ghost is sliding (capture key present), remember the last residual.
      for (int i = 0; i < 30; i++) {
        if (render.debugLastPhantomGhostPaint.containsKey("x")) {
          final farSide = _farSideVisible(render, "x", true);
          expect(farSide, lessThan(0.5),
              reason: "[fav frame $i] tall card leaked $farSide px ABOVE the "
                  "destination header band (FAR side) — far overhang not clipped");
          lastFarSide = farSide;
        }
        if (!c.hasActiveSlides) break;
        await tester.pump(const Duration(milliseconds: 16));
      }

      // The ghost must have actually slid (so the per-frame oracle ran).
      expect(lastFarSide, isNotNull,
          reason: "Test setup: ghost should have slid (capture populated)");

      // SETTLE — capture is empty (ghost pruned; Invariant 8). Do NOT deref.
      await tester.pumpAndSettle();
      expect(render.debugLastPhantomGhostPaint.containsKey("x"), isFalse,
          reason: "Capture must be gone at settle (ghost pruned)");
      expect(lastFarSide!, lessThan(0.5),
          reason: "FAR side must have converged on the final sliding frame");
      expect(c.visibleNodes.contains("x"), isFalse,
          reason: "Card must be fully hidden inside the collapsed section");
    },
  );

  testWidgets(
    "UNFAVORITE: tall card slides DOWN, FAR side occluded per-frame, "
    "fully occluded at settle",
    (tester) async {
      var fav = true; // true = x in favorites
      List<SyncedTreeNode<String, String>> build() => fav
          ? [_n("fav", [_n("x")]), _n("others", [_n("o1")])]
          : [_n("fav", [_n("fav_ph")]), _n("others", [_n("x"), _n("o1")])];

      await tester.pumpWidget(_Harness(builder: build));
      await tester.pumpAndSettle();
      final c = tester.state<_HarnessState>(find.byType(_Harness)).controller!;

      c.collapse(key: "others", animate: false);
      await tester.pump();

      // Unfavorite: x moves DOWN into collapsed others; fav -> placeholder.
      fav = false;
      await tester.pumpWidget(_Harness(builder: build));
      await tester.pump();

      final render = _render(tester);
      double? lastFarSide;

      for (int i = 0; i < 30; i++) {
        if (render.debugLastPhantomGhostPaint.containsKey("x")) {
          final farSide = _farSideVisible(render, "x", false);
          expect(farSide, lessThan(0.5),
              reason: "[unfav frame $i] tall card leaked $farSide px BELOW the "
                  "destination header band (FAR side) — far overhang not clipped");
          lastFarSide = farSide;
        }
        if (!c.hasActiveSlides) break;
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(lastFarSide, isNotNull,
          reason: "Test setup: ghost should have slid (capture populated)");

      await tester.pumpAndSettle();
      expect(render.debugLastPhantomGhostPaint.containsKey("x"), isFalse,
          reason: "Capture must be gone at settle (ghost pruned)");
      expect(lastFarSide!, lessThan(0.5),
          reason: "FAR side must have converged on the final sliding frame");
      expect(c.visibleNodes.contains("x"), isFalse,
          reason: "Card must be fully hidden inside the collapsed section");
    },
  );
}
