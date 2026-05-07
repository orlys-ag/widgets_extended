/// Regression tests for stale `parentData.indent` on off-cache mounted
/// rows whose depth changed via reparent.
///
/// Symptom: when a row's depth changes (cross-parent reparent under
/// `moveNode(animate: true)`), the engine installs an X-axis slide whose
/// composed `currentDeltaX` is a relative offset against the row's
/// **post-mutation** indent. Paint computes painted-X as
/// `parentData.indent + slideDeltaX`. For rows that ended up off the
/// cache region post-mutation, `_layoutNodeChild` is never called for
/// them, so `parentData.indent` keeps its **pre-mutation** value, and
/// painted-X is `oldIndent + (oldIndent - newIndent) = 2*oldIndent -
/// newIndent` at t=0 of the slide — visibly wrong.
///
/// The existing off-cache refresh loop in `performLayout` only updates
/// `parentData.layoutOffset`; it does not refresh indent.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const _kRowHeight = 50.0;
const _kViewportHeight = 500.0;
const _kIndentWidth = 24.0;

Widget _harness(
  TreeController<String, int> controller, {
  ScrollController? scrollController,
  double height = _kViewportHeight,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: height,
        child: CustomScrollView(
          controller: scrollController,
          cacheExtent: 0.0,
          slivers: <Widget>[
            SliverTree<String, int>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: _kRowHeight,
                  child: Padding(
                    padding: EdgeInsets.only(left: depth * _kIndentWidth),
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

/// Reads the parentData.indent for [nodeId] from the render object.
double? _indentForNodeId(WidgetTester tester, String nodeId) {
  final render = tester.renderObject<RenderSliverTree<String, int>>(
    find.byType(SliverTree<String, int>),
  );
  final box = render.getChildForNode(nodeId);
  if (box == null) return null;
  final pd = box.parentData;
  if (pd is! SliverTreeParentData) return null;
  return pd.indent;
}

void main() {
  group("off-cache mounted row with depth change keeps stale indent", () {
    testWidgets(
      "depth-change reparent, mid-flight: off-cache mounted row's "
      "parentData.indent reflects the POST-mutation depth (not the "
      "pre-mutation depth)",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = TreeController<String, int>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 800),
          animationCurve: Curves.linear,
          indentWidth: _kIndentWidth,
        );
        addTearDown(controller.dispose);

        // Build: 4 root parents, p0 has 3 nested grandchildren under
        // p0c0, p1..p3 each have 12 children. Visible total ≈ 46 rows.
        controller.runBatch(() {
          controller.setRoots([
            for (var i = 0; i < 4; i++)
              TreeNode<String, int>(key: "p$i", data: i),
          ]);
          controller.setChildren("p0", [
            const TreeNode<String, int>(key: "p0c0", data: 0),
            const TreeNode<String, int>(key: "p0c1", data: 1),
            const TreeNode<String, int>(key: "p0c2", data: 2),
          ]);
          controller.setChildren("p0c0", [
            for (var i = 0; i < 3; i++)
              TreeNode<String, int>(key: "p0c0g$i", data: i),
          ]);
          controller.expand(key: "p0", animate: false);
          controller.expand(key: "p0c0", animate: false);
          for (var p = 1; p < 4; p++) {
            controller.setChildren("p$p", [
              for (var c = 0; c < 12; c++)
                TreeNode<String, int>(key: "p${p}c$c", data: c),
            ]);
            controller.expand(key: "p$p", animate: false);
          }
        });
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();

        // Sanity: target row "p1c0" exists, depth 1, indent 24.
        // Pre-move it's at structural y = 4 (parents) + 3 (p0 children) +
        // 3 (p0c0 grandchildren) + 1 (p1) = 11 rows × 50 = 550 px.
        // Scroll so p1c0 is visible to start.
        scroll.jumpTo(300);
        await tester.pump();
        await tester.pumpAndSettle();
        // Viewport [300, 800] → p1c0 at 550 is visible at viewport-y=250.
        expect(find.byKey(const ValueKey("row-p1c0")), findsOneWidget);
        expect(_indentForNodeId(tester, "p1c0"), closeTo(24.0, 0.001));

        // Move p1c0 to be a grandchild under p0c0 at depth 2 (new indent
        // 48). The row's new structural Y depends on the new tree shape:
        // p0 (0) + p0c0 (50) + p1c0 NEW (100) + p0c0g0..g2 + p0c1 + p0c2
        // + ... — p1c0 lands around y=100 in scroll-space.
        controller.moveNode(
          "p1c0",
          "p0c0",
          index: 0,
          animate: true,
          slideDuration: const Duration(milliseconds: 800),
          slideCurve: Curves.linear,
        );
        await tester.pump();

        // After mutation: p1c0's NEW structural y ≈ 100. Viewport
        // [300, 800]. p1c0 is now off-screen ABOVE viewport. The slide-
        // OUT installs (priorOn: 550 in viewport, currOn: 100 not in
        // viewport) — likely an edge ghost via the top edge. The row's
        // new depth is 2.
        //
        // For the SLIDING painted X to be correct mid-flight, paint
        // requires `parentData.indent = 48` (new depth's indent).
        // Without the fix, parentData.indent stays at 24 (old depth)
        // for off-cache rows, and the painted X at slide t=0 is
        // 24 + (24 - 48) = 0. Visibly: row appears at the LEFT edge of
        // the sliver instead of indented.
        await tester.pump(const Duration(milliseconds: 50));

        final indentMid = _indentForNodeId(tester, "p1c0");
        expect(indentMid, isNotNull,
            reason: "p1c0 must be retained mid-slide");
        expect(indentMid, closeTo(48.0, 0.001),
            reason: "Mid-slide, parentData.indent for the off-cache "
                "moved row must reflect the POST-mutation depth (2 → "
                "indent 48). Got ${indentMid?.toStringAsFixed(1)}. "
                "Stale indent (24) means the row paints at the wrong "
                "X position throughout the slide and snaps to the "
                "correct X only at settle.");

        await tester.pumpAndSettle();
      },
    );
  });
}
