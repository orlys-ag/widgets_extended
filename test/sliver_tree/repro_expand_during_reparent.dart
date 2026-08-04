/// Probe: what happens when a node is reparented into a COLLAPSED section and
/// that section then EXPANDS while the exit-slide is still in flight?
///
/// This is a different path from the "stays collapsed" exit-phantom bug:
/// once the row re-enters the visible set, the controller abandons the
/// exit-ghost (render_sliver_tree.dart:693, 805-815) and the standard slide
/// path is supposed to take over. We characterize whether the hand-off is
/// continuous (no jump) and settles correctly.
library;

import 'package:widgets_extended/sliver_tree/animation_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/render_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree_widget.dart';
import 'package:widgets_extended/sliver_tree/synced_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/synced_tree_node.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

SyncedTreeNode<String, String> _n(String k,
        [List<SyncedTreeNode<String, String>>? c]) =>
    SyncedTreeNode(key: k, data: k, children: c ?? const []);

/// painted Y = layoutOffset (+ slide delta if the row is mounted) — but we
/// read layoutOffset for visible rows and fall back to slide delta for ghosts.
({double? offset, double? extent}) _probe(
    WidgetTester tester, String key) {
  final render = tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
  double? off;
  double? ext;
  render.visitChildren((child) {
    if (child is! RenderBox) return;
    final pd = child.parentData as SliverTreeParentData;
    if (pd.nodeId == key) {
      off = pd.layoutOffset;
      ext = pd.visibleExtent;
    }
  });
  return (offset: off, extent: ext);
}

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
              animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 400), curve: Curves.linear)),
              itemBuilder: (context, node) {
                controller ??= node.controller;
                return SizedBox(
                  key: ValueKey("row-${node.key}"),
                  height: 48,
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

void _log(WidgetTester t, TreeController c, String tag) {
  final x = _probe(t, "x");
  // ignore: avoid_print
  print("$tag visible(x)=${c.visibleNodes.contains("x")} "
      "slideDelta(x)=${c.getSlideDelta("x").toStringAsFixed(1)} "
      "offset=${x.offset?.toStringAsFixed(1)} "
      "extent=${x.extent?.toStringAsFixed(1)} "
      "paintedY=${x.offset == null ? "?" : (x.offset! + c.getSlideDelta("x")).toStringAsFixed(1)}");
}

void main() {
  testWidgets("expand collapsed section WHILE exit-slide is in flight",
      (tester) async {
    var fav = true;
    await tester.pumpWidget(_Harness(builder: () => fav
        ? [_n("fav", [_n("x"), _n("keep")]), _n("others", [_n("o1")])]
        : [_n("fav", [_n("keep")]), _n("others", [_n("x"), _n("o1")])]));
    await tester.pumpAndSettle();
    final c =
        tester.state<_HarnessState>(find.byType(_Harness)).controller!;

    // Collapse others.
    c.collapse(key: "others", animate: false);
    await tester.pump();
    _log(tester, c, "[after collapse]");

    // Un-favorite x -> exit-slide into collapsed others (Case B: delta works).
    fav = false;
    await tester.pumpWidget(_Harness(builder: () =>
        [_n("fav", [_n("keep")]), _n("others", [_n("x"), _n("o1")])]));
    await tester.pump();
    _log(tester, c, "[move t=0]");

    // Let the exit-slide run halfway.
    await tester.pump(const Duration(milliseconds: 200));
    _log(tester, c, "[mid-slide t=200]");

    // Now EXPAND others mid-slide.
    c.expand(key: "others", animate: true);
    await tester.pump();
    _log(tester, c, "[expand+0]");
    await tester.pump(const Duration(milliseconds: 16));
    _log(tester, c, "[expand+16]");
    await tester.pump(const Duration(milliseconds: 100));
    _log(tester, c, "[expand+116]");

    await tester.pumpAndSettle();
    _log(tester, c, "[settled]");
    // After settle x must be visible in the expanded section at a stable spot.
    expect(c.visibleNodes.contains("x"), true);
  });

  testWidgets("move + expand in the SAME batch (controller level)",
      (tester) async {
    final c = TreeController<String, String>(
      vsync: tester,
      animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 400), curve: Curves.linear)),
    );
    addTearDown(c.dispose);
    c.setRoots([const TreeNode(key: "A", data: "A"), const TreeNode(key: "B", data: "B")]);
    c.setChildren("A", [const TreeNode(key: "x", data: "x"), const TreeNode(key: "keep", data: "keep")]);
    c.setChildren("B", [const TreeNode(key: "o1", data: "o1")]);
    c.expand(key: "A", animate: false);
    // B collapsed.

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(slivers: [
            SliverTree<String, String>(
              controller: c,
              nodeBuilder: (context, key, depth) =>
                  SizedBox(key: ValueKey("row-$key"), height: 48, child: Text(key)),
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Same batch: move x into B AND expand B.
    c.runBatch(() {
      c.moveNode("x", "B", index: 0, animate: true);
      c.expand(key: "B", animate: true);
    });
    await tester.pump();
    _log(tester, c, "[batch move+expand t=0]");
    await tester.pump(const Duration(milliseconds: 100));
    _log(tester, c, "[t=100]");
    await tester.pump(const Duration(milliseconds: 100));
    _log(tester, c, "[t=200]");
    await tester.pumpAndSettle();
    _log(tester, c, "[settled]");
    expect(c.visibleNodes.contains("x"), true);
  });
}
