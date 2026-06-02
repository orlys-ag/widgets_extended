/// Asserting copy of `repro_workspace_reparent_collapsed.dart`.
///
/// Promotes the Clarity workspaces reparent-into-collapsed-section
/// characterization to hard assertions for Bug 1 (settled-destination
/// exit-slide). The companion repro file keeps the `print`-based diagnostics
/// for manual inspection; this file is collected by `flutter test`.
///
/// Mirrors the app: declarative `.tree` mode, two persistent root sections,
/// the source section collapses to a single placeholder child when emptied,
/// and `maxStickyDepth: 1`. Rows are 48 px; the settled exit-slide distance
/// from the just-vacated `fav` slot into the collapsed `others` header is
/// `-48`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/synced_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/synced_tree_node.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';

SyncedTreeNode<String, String> _n(String k,
        [List<SyncedTreeNode<String, String>>? c]) =>
    SyncedTreeNode(key: k, data: k, children: c ?? const []);

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
  // enters) and moves x into collapsed others. The exit-slide destination must
  // be sampled at the SETTLED anchor position (-48), not the transient one (0).
  testWidgets(
    "A: fav->placeholder, x slides settled -48 into collapsed others",
    (tester) async {
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

      // At t=0 the exit slide must install the full settled distance.
      expect(c.hasActiveSlides, true);
      expect(c.getSlideDelta("x"), moreOrLessEquals(-48.0, epsilon: 0.5));

      // Mid-animation the ghost must actually traverse: strictly between the
      // start (-48) and the settle (0), i.e. real motion is happening.
      await tester.pump(const Duration(milliseconds: 200));
      final mid = c.getSlideDelta("x");
      expect(mid, greaterThan(-48.0));
      expect(mid, lessThan(0.0));

      // Settles to 0 and x ends hidden inside the collapsed section.
      await tester.pumpAndSettle();
      expect(c.getSlideDelta("x"), moreOrLessEquals(0.0, epsilon: 0.5));
      expect(c.visibleNodes.contains("x"), false);
    },
  );

  // CASE B — control: fav has x AND keep; un-favorite x leaves fav non-empty
  // (no placeholder, `keep` shifts instantly), x into collapsed others. The
  // settled distance is unchanged at -48; this guards against regressing the
  // already-working non-placeholder path.
  testWidgets(
    "B: fav stays non-empty, x slides -48 into collapsed others",
    (tester) async {
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

      expect(c.hasActiveSlides, true);
      expect(c.getSlideDelta("x"), moreOrLessEquals(-48.0, epsilon: 0.5));

      await tester.pumpAndSettle();
      expect(c.getSlideDelta("x"), moreOrLessEquals(0.0, epsilon: 0.5));
      expect(c.visibleNodes.contains("x"), false);
    },
  );

  // CASE C — fav empties to NOTHING (header-only, no placeholder child). The
  // genuine settled distance is ~0, so NO slide must be fabricated. This is a
  // hard guard, not a heuristic: the settled-destination fix must not invent
  // motion here.
  testWidgets(
    "C: fav->empty header-only, no fabricated slide",
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

      // No fabricated slide at t=0.
      expect(c.getSlideDelta("x").abs(), lessThan(0.5));

      // And no ghost motion fabricated during the animation window.
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.getSlideDelta("x").abs(), lessThan(0.5));

      await tester.pumpAndSettle();
      expect(c.getSlideDelta("x").abs(), lessThan(0.5));
      expect(c.visibleNodes.contains("x"), false);
    },
  );
}
