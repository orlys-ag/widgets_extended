/// Characterization of the Clarity workspaces bug:
/// reparenting an item from the (expanded) favorites section into the
/// COLLAPSED "others" section. Expected: the card slides into the collapsed
/// section header (exit-phantom). Observed in-app: it disappears instantly.
///
/// Mirrors the app: declarative `.tree` mode, two persistent root sections,
/// the source section collapses to a single placeholder child when emptied,
/// and `maxStickyDepth: 1`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/render_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree_widget.dart';
import 'package:widgets_extended/sliver_tree/synced_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/synced_tree_node.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

SyncedTreeNode<String, String> _n(String k, [List<SyncedTreeNode<String, String>>? c]) =>
    SyncedTreeNode(key: k, data: k, children: c ?? const []);

double? _extentOf(WidgetTester tester, String key, TreeController c) {
  final render = tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
  double? out;
  render.visitChildren((child) {
    if (child is! RenderBox) return;
    final pd = child.parentData as SliverTreeParentData;
    if (pd.nodeId == key) out = pd.visibleExtent;
  });
  return out;
}

double? _offsetOf(WidgetTester tester, String key, TreeController c) {
  final render = tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
  double? out;
  render.visitChildren((child) {
    if (child is! RenderBox) return;
    final pd = child.parentData as SliverTreeParentData;
    if (pd.nodeId == key) out = pd.layoutOffset;
  });
  return out;
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
              animationDuration: const Duration(milliseconds: 400),
              animationCurve: Curves.linear,
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

Future<TreeController<String, String>> _pump(
  WidgetTester tester,
  List<SyncedTreeNode<String, String>> Function() builder,
) async {
  await tester.pumpWidget(_Harness(builder: builder));
  return tester.state<_HarnessState>(find.byType(_Harness)).controller!;
}

void main() {
  // CASE A — the bug: fav has only x; un-favorite empties fav (placeholder
  // enters) and moves x into collapsed others.
  testWidgets("A: fav->placeholder, x into collapsed others", (tester) async {
    var fav = true;
    final c = await _pump(tester, () => fav
        ? [_n("fav", [_n("x")]), _n("others", [_n("o1")])]
        : [_n("fav", [_n("fav_ph")]), _n("others", [_n("x"), _n("o1")])]);
    await tester.pumpAndSettle();

    c.collapse(key: "others", animate: false);
    await tester.pump();

    fav = false;
    await tester.pumpWidget(_Harness(builder: () =>
        [_n("fav", [_n("fav_ph")]), _n("others", [_n("x"), _n("o1")])]));
    await tester.pump();

    // ignore: avoid_print
    print("[A] hasActiveSlides=${c.hasActiveSlides} "
        "slideDelta(x)=${c.getSlideDelta("x")} "
        "fav_ph extent@consume=${_extentOf(tester, "fav_ph", c)} "
        "others offset@consume=${_offsetOf(tester, "others", c)} "
        "fav_ph extent@consume2=${_extentOf(tester, "fav_ph", c)}");
    await tester.pump(const Duration(milliseconds: 200));
    // ignore: avoid_print
    print("[A] mid-anim: others offset=${_offsetOf(tester, "others", c)} "
        "fav_ph extent=${_extentOf(tester, "fav_ph", c)} "
        "slideDelta(x)=${c.getSlideDelta("x")}");
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print("[A] settled: others offset=${_offsetOf(tester, "others", c)} "
        "fav_ph extent=${_extentOf(tester, "fav_ph", c)}");
  });

  // CASE B — control: fav has x AND keep; un-favorite x leaves fav non-empty
  // (no placeholder, `keep` shifts instantly), x into collapsed others.
  testWidgets("B: fav stays non-empty, x into collapsed others", (tester) async {
    var fav = true;
    final c = await _pump(tester, () => fav
        ? [_n("fav", [_n("x"), _n("keep")]), _n("others", [_n("o1")])]
        : [_n("fav", [_n("keep")]), _n("others", [_n("x"), _n("o1")])]);
    await tester.pumpAndSettle();

    c.collapse(key: "others", animate: false);
    await tester.pump();

    fav = false;
    await tester.pumpWidget(_Harness(builder: () =>
        [_n("fav", [_n("keep")]), _n("others", [_n("x"), _n("o1")])]));
    await tester.pump();

    // ignore: avoid_print
    print("[B] hasActiveSlides=${c.hasActiveSlides} "
        "slideDelta(x)=${c.getSlideDelta("x")}");
    await tester.pumpAndSettle();
  });

  // CASE C — fav empties to NOTHING (no placeholder child at all).
  testWidgets("C: fav->empty (no placeholder), x into collapsed others",
      (tester) async {
    var fav = true;
    final c = await _pump(tester, () => fav
        ? [_n("fav", [_n("x")]), _n("others", [_n("o1")])]
        : [_n("fav"), _n("others", [_n("x"), _n("o1")])]);
    await tester.pumpAndSettle();

    c.collapse(key: "others", animate: false);
    await tester.pump();

    fav = false;
    await tester.pumpWidget(_Harness(builder: () =>
        [_n("fav"), _n("others", [_n("x"), _n("o1")])]));
    await tester.pump();

    // ignore: avoid_print
    print("[C] hasActiveSlides=${c.hasActiveSlides} "
        "slideDelta(x)=${c.getSlideDelta("x")}");
    await tester.pumpAndSettle();
  });
}
