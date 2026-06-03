/// Entry-phantom non-regression guard (Invariant 9): the EXIT-role band/
/// far-overhang clip rework MUST NOT leak into the ENTRY role.
///
/// A collapsed->visible reparent (ENTRY) makes a previously-hidden row
/// EMERGE past its anchor. With NON-UNIFORM heights (48px anchor header,
/// 80px emerging row) the row must stay VISIBLE on the DESTINATION side of
/// its anchor during the slide (the legacy half-plane clip), and the
/// visible extent must GROW as the row slides away from the anchor. This
/// is the OPPOSITE of the exit oracle and proves `PhantomClipRole.entry`
/// routes to the verbatim legacy clip.
///
/// ORACLE: the entry row is an in-flow `visibleNodes` member, so it does
/// NOT appear in `debugLastPhantomGhostPaint` (that map is EXIT-only).
/// Instead a recording `PaintingContext` captures the clip rect the
/// render pushes for the entry row's child in `_paintRow`, paired with the
/// child's painted offset, and we measure the row's clipped (visible)
/// extent on the destination side. Y's painted top is read independently
/// from the controller (`layoutOffset + getSlideDelta`) to match the clip
/// to Y's child.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const double _kHeader = 48.0;
const double _kRow = 80.0;

double _heightFor(String key) => key == "A" || key == "B" ? _kHeader : _kRow;

/// A no-draw recording `PaintingContext`. `paintChild` records the child's
/// paint offset (and which clip band, if any, encloses it) WITHOUT
/// recursing into a real canvas; `pushClipRect` records the clip band and
/// runs the painter with `this` so nested `paintChild`s land back here.
class _Recorder extends PaintingContext {
  _Recorder(super.containerLayer, super.estimatedBounds);

  /// (childTop, enclosingClip) — enclosingClip null when unclipped. All in
  /// render-local (sliver paint-offset) coords.
  final List<({double childTop, Rect? clip})> children = [];
  Rect? _currentClip;

  @override
  ClipRectLayer? pushClipRect(
    bool needsCompositing,
    Offset offset,
    Rect clipRect,
    PaintingContextCallback painter, {
    Clip clipBehavior = Clip.hardEdge,
    ClipRectLayer? oldLayer,
  }) {
    final prev = _currentClip;
    _currentClip = clipRect.shift(offset);
    painter(this, offset);
    _currentClip = prev;
    return null;
  }

  @override
  void paintChild(RenderObject child, Offset offset) {
    children.add((childTop: offset.dy, clip: _currentClip));
    // Intentionally do NOT recurse — we only need the offset + clip band.
  }
}

Widget _harness(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: CustomScrollView(
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              // maxStickyDepth 0 so NO sticky / Pass-A.7 header repaint
              // applies to the entry anchor (entry case has no repaint).
              maxStickyDepth: 0,
              nodeBuilder: (_, key, depth) => SizedBox(
                key: ValueKey("row-$key"),
                height: _heightFor(key),
                child: Padding(
                  padding: EdgeInsets.only(left: depth * 20.0),
                  child: Text(key),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Y's painted top this frame in sliver-local coords, read from the render
/// object's parent data + the controller's slide delta.
double _paintedTop(
    RenderSliverTree<String, String> render, TreeController<String, String> c,
    String key) {
  double? off;
  render.visitChildren((child) {
    if (child is! RenderBox) return;
    final pd = child.parentData as SliverTreeParentData;
    if (pd.nodeId == key) off = pd.layoutOffset;
  });
  // Viewport not scrolled, so sliver-local == layoutOffset + slideDelta.
  return (off ?? 0) + c.getSlideDelta(key);
}

void main() {
  testWidgets(
    "entry phantom (collapsed->visible) still emerges past its anchor; "
    "band rework is exit-only",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // A (collapsed, 48px header) [Y (80px)]; B (expanded, 48px) [b1].
      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
      ]);
      controller.setChildren("A", [const TreeNode(key: "Y", data: "Y")]);
      controller.setChildren("B", [const TreeNode(key: "b1", data: "b1")]);
      controller.expand(key: "B", animate: false);
      // A stays collapsed → Y hidden.

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();
      expect(controller.visibleNodes.contains("Y"), false);

      // Reparent Y to B at index 0 (collapsed -> visible ENTRY phantom).
      controller.moveNode(
        "Y",
        "B",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump();
      expect(controller.visibleNodes.contains("Y"), true);
      expect(controller.hasActiveSlides, true);

      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );

      // Measure Y's destination-side visible (clipped) extent by re-painting
      // through a no-draw recorder. The entry clip half-plane bounds Y to
      // the side of its anchor where it currently paints; as Y slides away
      // the visible extent GROWS.
      double measureVisibleExtent() {
        final yTop = _paintedTop(render, controller, "Y");
        final recorder = _Recorder(
          ContainerLayer(),
          Offset.zero & const Size(400, 600),
        );
        render.paint(recorder, Offset.zero);
        // Y is the ENTRY-phantom-clipped row: it's the only child painted
        // inside an entry clip band at childTop ≈ yTop. Headers (A/B) paint
        // UNCLIPPED in the standard pass and may share a Y position, so
        // match the record that BOTH sits at yTop AND carries a clip band.
        ({double childTop, Rect? clip})? hit;
        for (final rec in recorder.children) {
          if ((rec.childTop - yTop).abs() >= 1.0) continue;
          if (rec.clip != null) {
            hit = rec;
            break;
          }
          hit ??= rec; // fallback: unclipped row at yTop
        }
        if (hit == null) return -1.0; // Y's child not found this frame
        final rowTop = yTop;
        final rowBottom = yTop + _kRow;
        if (hit.clip == null) return _kRow; // unclipped — fully visible
        final visTop = rowTop > hit.clip!.top ? rowTop : hit.clip!.top;
        final visBottom =
            rowBottom < hit.clip!.bottom ? rowBottom : hit.clip!.bottom;
        final ext = visBottom - visTop;
        return ext > 0 ? ext : 0.0;
      }

      // Partway through the slide (Y has begun emerging past its anchor):
      // the destination-side visible extent must be > 0 — the legacy
      // half-plane reveals it; the band rework did NOT clip it to zero.
      await tester.pump(const Duration(milliseconds: 100));
      final early = measureVisibleExtent();
      expect(early, greaterThan(0.0),
          reason: "Entry row must be VISIBLE on the destination side of its "
              "anchor as it emerges (legacy half-plane, NOT band-clipped to "
              "zero). Got $early.");
      expect(early, lessThan(_kRow),
          reason: "Test setup: Y should be only PARTLY emerged at ~100ms so "
              "growth is observable. Got $early.");

      // Advance the slide; the visible extent must GROW as Y slides away
      // from its anchor.
      await tester.pump(const Duration(milliseconds: 150));
      final later = measureVisibleExtent();
      expect(later, greaterThan(early),
          reason: "Entry row's destination-side visible extent must GROW as "
              "it emerges past its anchor. early=$early later=$later.");

      await tester.pumpAndSettle();
      // Fully emerged: Y visible.
      expect(controller.visibleNodes.contains("Y"), true);
    },
  );
}
