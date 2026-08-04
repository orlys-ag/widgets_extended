/// Asserting copy of `repro_expand_during_reparent.dart`.
///
/// Promotes the "expand a collapsed section while an exit-slide is still in
/// flight" characterization to a painted-position-continuity assertion (Bug 2),
/// and adds the symmetric case (collapse a section while an entry-slide is in
/// flight). The companion repro file keeps the `print`-based diagnostics for
/// manual inspection; this file is collected by `flutter test`.
///
/// Rows are 48 px, the slide duration is 400 ms, and the test binding pumps at
/// the default 60 Hz (16 ms/frame). The per-frame painted step is therefore
/// bounded by roughly `48 px * 16/400 = 1.9 px`; we assert `<= 6.0` to leave
/// slack for the op-group extent envelope and frame-boundary rounding. A
/// teleport (the un-fixed Bug 2) is a single-frame jump of ~one row height
/// (48 px), well above the bound.
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

const double _kRow = 48.0;

/// Per-16 ms-frame painted bound. A teleport (the un-fixed Bug 2) is a
/// single-frame jump of ~one row height (48 px); legitimate slide motion is
/// `48 px * 16/400 ≈ 1.9 px` per frame. `6.0` gives ample slack over the
/// op-group extent envelope and frame-boundary rounding while staying far
/// below a teleport. Intervals longer than one frame scale the bound by the
/// number of 16 ms frames they span (the plan's sample schedule includes a
/// 100 ms interval, which legitimately accumulates ~12 px of smooth motion).
const double _kPerFrameBound = 6.0;
const double _kFrameMs = 16.0;

({double? offset, double? extent}) _probe(WidgetTester tester, String key) {
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

/// Painted Y of [key], switching oracle at the exact frame its visibility
/// flips (the hand-off being tested):
/// - visible row: `layoutOffset + slideDelta(key)`.
/// - exit/entry ghost (not in visibleNodes): mirror Pass A.5's paint formula
///   `anchorSettledTop + slideDelta(key)` where [anchor] is the deepest
///   visible ancestor. The SETTLED top is the anchor's structural
///   `layoutOffset` WITHOUT the anchor's own slide delta — the ghost
///   converges on the settled position; the anchor's live band only drives
///   the exit clip (see `_exitGhostPaintedBaseScrollSpace`). The
///   direction-aware tuck is 0 here (all rows share the same height).
double? _paintedY(
  WidgetTester tester,
  TreeController<String, String> c,
  String key,
  String anchor,
) {
  if (c.visibleNodes.contains(key)) {
    final p = _probe(tester, key);
    if (p.offset == null) return null;
    return p.offset! + c.getSlideDelta(key);
  }
  // Ghost: anchored to its visible ancestor's settled top.
  final a = _probe(tester, anchor);
  if (a.offset == null) return null;
  return a.offset! + c.getSlideDelta(key);
}

/// Asserts painted-Y continuity across consecutive [samples]. [intervalMs] is
/// the elapsed time (ms) between sample `i` and `i+1`; the per-interval bound
/// scales with the number of 16 ms frames it spans so a 100 ms interval is not
/// held to a single-frame bound. The check catches a teleport (a within-frame
/// jump of ~one row height) while permitting legitimate smooth motion.
void _expectContinuous(
  List<double?> samples,
  List<double> intervalMs,
  String label,
) {
  assert(intervalMs.length == samples.length - 1);
  for (var i = 0; i < samples.length - 1; i++) {
    final a = samples[i];
    final b = samples[i + 1];
    expect(a, isNotNull, reason: "$label: sample $i is null");
    expect(b, isNotNull, reason: "$label: sample ${i + 1} is null");
    final step = (b! - a!).abs();
    final frames = (intervalMs[i] / _kFrameMs).ceil().clamp(1, 1 << 30);
    final bound = _kPerFrameBound * frames;
    expect(
      step,
      lessThanOrEqualTo(bound),
      reason: "$label: painted jump between sample $i ($a) and "
          "${i + 1} ($b) = $step px exceeds $bound px over "
          "${intervalMs[i]} ms ($frames frames) — teleport",
    );
  }
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
                  height: _kRow,
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

void main() {
  testWidgets(
    "expand collapsed section mid exit-slide hands off continuously",
    (tester) async {
      var fav = true;
      await tester.pumpWidget(_Harness(builder: () => fav
          ? [_n("fav", [_n("x"), _n("keep")]), _n("others", [_n("o1")])]
          : [_n("fav", [_n("keep")]), _n("others", [_n("x"), _n("o1")])]));
      await tester.pumpAndSettle();
      final c = tester.state<_HarnessState>(find.byType(_Harness)).controller!;

      // Collapse others.
      c.collapse(key: "others", animate: false);
      await tester.pump();

      // Un-favorite x -> exit-slide into the collapsed `others` header.
      fav = false;
      await tester.pumpWidget(_Harness(builder: () =>
          [_n("fav", [_n("keep")]), _n("others", [_n("x"), _n("o1")])]));
      await tester.pump();

      // Let the exit-slide run partway, then sample painted-Y across the
      // expand hand-off and the final settle.
      await tester.pump(const Duration(milliseconds: 200));
      final samples = <double?>[];
      final intervals = <double>[];
      samples.add(_paintedY(tester, c, "x", "others")); // [mid-slide]

      // Expand others mid-slide — this is the base change that used to
      // teleport x. The mid-slide → expand+0 step is the hand-off frame: the
      // teleport, if any, manifests here.
      c.expand(key: "others", animate: true);
      await tester.pump();
      samples.add(_paintedY(tester, c, "x", "others")); // [expand+0]
      intervals.add(_kFrameMs); // single-frame hand-off
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(_paintedY(tester, c, "x", "others")); // [expand+16]
      intervals.add(16);
      await tester.pump(const Duration(milliseconds: 100));
      samples.add(_paintedY(tester, c, "x", "others")); // [expand+116]
      intervals.add(100);

      // Remaining slide after [expand+116]: started at t≈200 ms of a 400 ms
      // exit slide, recomposed on expand, ~84 ms left after +116. Allow the
      // full residual window.
      await tester.pumpAndSettle();
      samples.add(_paintedY(tester, c, "x", "others")); // [settled]
      intervals.add(400);

      _expectContinuous(samples, intervals, "expand-mid-exit-slide");

      // x ends visible inside the now-expanded section at its settled
      // structural offset.
      expect(c.visibleNodes.contains("x"), true);
      final settledProbe = _probe(tester, "x");
      expect(settledProbe.offset, isNotNull);
      expect(c.getSlideDelta("x"), moreOrLessEquals(0.0, epsilon: 0.5));
      expect(
        samples.last!,
        moreOrLessEquals(settledProbe.offset!, epsilon: 0.5),
      );
    },
  );

  testWidgets(
    "collapse expanding section mid entry-slide hands off continuously",
    (tester) async {
      // Symmetric case: x starts hidden under a collapsed `others`; we move it
      // into `fav` (visible) AND expand nothing — instead we reverse the
      // scenario: x lives in an expanded `others`, gets reparented into `fav`
      // producing an entry-slide, and `fav` is collapsed mid-entry.
      //
      // Build state: x hidden in collapsed `others`; reparent x into `fav`
      // (visible) so it enters with a slide, then collapse `fav` mid-entry.
      var moved = false;
      await tester.pumpWidget(_Harness(builder: () => moved
          ? [_n("fav", [_n("keep"), _n("x")]), _n("others", [_n("o1")])]
          : [_n("fav", [_n("keep")]), _n("others", [_n("x"), _n("o1")])]));
      await tester.pumpAndSettle();
      final c = tester.state<_HarnessState>(find.byType(_Harness)).controller!;

      // x is currently in `others`. Reparent x into `fav` to trigger an
      // entry-slide into the visible `fav` section.
      moved = true;
      await tester.pumpWidget(_Harness(builder: () =>
          [_n("fav", [_n("keep"), _n("x")]), _n("others", [_n("o1")])]));
      await tester.pump();

      // Run the entry-slide partway.
      await tester.pump(const Duration(milliseconds: 200));
      final samples = <double?>[];
      final intervals = <double>[];
      samples.add(_paintedY(tester, c, "x", "fav")); // [mid-entry]

      // Collapse `fav` mid-entry — base change while x is entry-sliding. The
      // mid-entry → collapse+0 step is the hand-off frame.
      c.collapse(key: "fav", animate: true);
      await tester.pump();
      samples.add(_paintedY(tester, c, "x", "fav")); // [collapse+0]
      intervals.add(_kFrameMs); // single-frame hand-off
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(_paintedY(tester, c, "x", "fav")); // [collapse+16]
      intervals.add(16);
      await tester.pump(const Duration(milliseconds: 100));
      samples.add(_paintedY(tester, c, "x", "fav")); // [collapse+116]
      intervals.add(100);

      // Continuity is asserted over the visible slide window only. The final
      // settle removes x from visible order entirely (it collapses into the
      // `fav` header and is purged), so there is no meaningful painted
      // position to compare against — the end state is asserted separately
      // below.
      _expectContinuous(samples, intervals, "collapse-mid-entry-slide");

      // x ends hidden (its parent `fav` is collapsed) with a settled slide.
      await tester.pumpAndSettle();
      expect(c.visibleNodes.contains("x"), false);
      expect(c.getSlideDelta("x"), moreOrLessEquals(0.0, epsilon: 0.5));
    },
  );
}
