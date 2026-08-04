/// Tests for the 2026-07-29 review, item 1: `findRowAtPaintedY`'s bounded
/// window scan. The make-room preview is a HELD offset, so
/// `hasActiveSlides` is true for an entire drag and the old routing ran
/// the O(N) full scan on every pointer event; the bounded scan restores
/// O(window) using `composedSlideAbsDeltaBound` (the SUM of the engine
/// maxima — a max-based bound under-estimates when a row carries both a
/// decaying commit-FLIP delta and a held preview offset).
///
/// Coverage:
/// - Oracle equivalence: the routed result must equal the exact full scan
///   (`debugFindRowFullScan`) for dense scrollY sweeps across composed
///   states — held preview (mid-animation and settled), FLIP+preview
///   overlap (the summed-bound case: a max bound regresses exactly here),
///   pending-deletion rows mid-exit, and past-the-end fallbacks with a
///   dead trailing row (the phase-1 lastLive / downward-walk fallbacks).
/// - Routing pins via `debugLastFindRowUsedFullScan`: bounded in the
///   steady drag state; full scan when a structural mutation has not been
///   laid out yet; bounded again after the pump.
/// - Window-size pin via `debugLastFindRowIterationCount`: O(window), not
///   O(N), on a 1000-row order — the regression contract against routing
///   re-widening.
///
/// Comparison discipline: sweeps run only in pumped, layout-settled
/// states — the bounded path reads layout-stamped extents, the oracle
/// reads controller truth, and the two are defined to agree only when a
/// layout has run since the last mutation/tick (the routing's staleness
/// condition guarantees exactly this in production). The tree is kept
/// small enough to be fully measured (viewport + cache), because for
/// never-measured rows the two extent sources legitimately differ — a
/// pre-existing fast-vs-slow-path property, not a bounded-scan one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const double _viewportHeight = 550.0;

double _heightFor(int i) => 30.0 + 6.0 * (i % 4);

Widget _harness(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: _viewportHeight,
        child: CustomScrollView(
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                final i = int.parse(key.substring(1));
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: _heightFor(i),
                  child: Text(key),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

RenderSliverTree<String, String> _sliver(WidgetTester tester) {
  return tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
}

/// Probe list: a coarse fixed-step sweep PLUS ε-probes around every
/// visible row's actual painted start/end (computed the same way the
/// oracle computes them). The boundary probes are what give the sweep
/// teeth — divergence bands between a broken window bound and the true
/// composed displacement can be narrower than any fixed step, but every
/// such band contains a painted boundary of some affected row.
List<double> _probeYs(
  TreeController<String, String> controller, {
  required double from,
  required double to,
  required double step,
}) {
  final probes = <double>[for (double y = from; y <= to; y += step) y];
  final nids = controller.orderNidsView;
  final n = controller.visibleNodeCount;
  double structural = 0.0;
  for (int i = 0; i < n; i++) {
    final nid = nids[i];
    final extent = controller.getCurrentExtentNid(nid);
    final painted = structural + controller.getSlideDeltaNid(nid);
    probes
      ..add(painted - 0.5)
      ..add(painted + 0.5)
      ..add(painted + extent - 0.5)
      ..add(painted + extent + 0.5);
    structural += extent;
  }
  return probes;
}

/// Asserts the routed result equals the exact full-scan oracle for every
/// probe. Reads the routed result FIRST — the oracle call clobbers the
/// shared debug iteration counter.
void _expectOracleEquivalence(
  RenderSliverTree<String, String> sliver,
  TreeController<String, String> controller,
  String state, {
  double from = -30.0,
  double to = 560.0,
  double step = 7.0,
}) {
  for (final y in _probeYs(controller, from: from, to: to, step: step)) {
    final actual = sliver.findRowAtPaintedY(y);
    final oracle = sliver.debugFindRowFullScan(y);
    if (oracle == null) {
      expect(actual, isNull, reason: "[$state] y=$y: oracle is null");
      continue;
    }
    expect(actual, isNotNull, reason: "[$state] y=$y: oracle=${oracle.key}");
    expect(actual!.key, oracle.key, reason: "[$state] y=$y");
    expect(
      actual.paintedOffset,
      closeTo(oracle.paintedOffset, 1e-6),
      reason: "[$state] y=$y key=${oracle.key}",
    );
    expect(
      actual.extent,
      closeTo(oracle.extent, 1e-6),
      reason: "[$state] y=$y key=${oracle.key}",
    );
  }
}

/// Largest |composed per-row delta| across the visible order — what the
/// bounded scan's window must actually cover.
double _maxComposedAbsDelta(TreeController<String, String> controller) {
  double maxAbs = 0.0;
  final nids = controller.orderNidsView;
  final n = controller.visibleNodeCount;
  for (int i = 0; i < n; i++) {
    final d = controller.getSlideDeltaNid(nids[i]).abs();
    if (d > maxAbs) {
      maxAbs = d;
    }
  }
  return maxAbs;
}

TreeController<String, String> _controller(WidgetTester tester) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: const TreeAnimationStyle(
      expandCollapse: TreeAnimationSpec(
        duration: Duration(milliseconds: 250),
        curve: Curves.linear,
      ),
      enterExit: TreeAnimationSpec(
        duration: Duration(milliseconds: 250),
        curve: Curves.linear,
      ),
      reorderSlide: TreeAnimationSpec(
        duration: Duration(milliseconds: 300),
        curve: Curves.linear,
      ),
      makeRoom: TreeAnimationSpec(
        duration: Duration(milliseconds: 200),
        curve: Curves.linear,
      ),
    ),
  );
  // Roots n0..n3; n1 and n2 carry expanded children — 11 rows total
  // (~420px), fully inside viewport + cache so every row is measured.
  controller.setRoots([
    for (int r = 0; r < 4; r++) TreeNode(key: "n$r", data: "N$r"),
  ]);
  controller.setChildren("n1", [
    for (int i = 4; i < 8; i++) TreeNode(key: "n$i", data: "N$i"),
  ]);
  controller.setChildren("n2", [
    for (int i = 8; i < 11; i++) TreeNode(key: "n$i", data: "N$i"),
  ]);
  controller.expand(key: "n1", animate: false);
  controller.expand(key: "n2", animate: false);
  return controller;
}

void main() {
  testWidgets("oracle equivalence across composed drag states",
      (tester) async {
    final controller = _controller(tester);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();
    final sliver = _sliver(tester);

    // S1a: held preview, gap animation mid-flight.
    controller.setReorderPreview(
      draggedKey: "n1",
      targetKey: "n3",
      gapBelowTarget: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    _expectOracleEquivalence(sliver, controller, "preview mid-animation");

    // Self-check: the sweep above must have exercised the BOUNDED path,
    // not fallen back (no ghosts, no staleness in this state).
    sliver.findRowAtPaintedY(100.0);
    expect(sliver.debugLastFindRowUsedFullScan, isFalse,
        reason: "setup: the steady preview state must route to the "
            "bounded scan");

    // S1b: held preview, settled hold.
    await tester.pump(const Duration(milliseconds: 250));
    _expectOracleEquivalence(sliver, controller, "preview settled hold");

    // S2: FLIP + preview overlap — the summed-bound case. Move n1's
    // 5-row subtree (~192px) past n2 so n2's subtree carries a LARGE
    // positive FLIP delta (the mover's own delta is smaller, so the
    // slide max comes from these rows), then hold a preview whose gap
    // sits above n2 so the SAME rows also carry a positive preview
    // shift. The composed per-row delta then EXCEEDS
    // max(slideMax, previewMax) — a max-based window bound excludes
    // these rows' true painted spans and returns wrong targets, which
    // the boundary probes catch.
    controller.clearReorderPreview(animate: false);
    controller.moveNode("n1", null, index: 2);
    await tester.pump();
    controller.setReorderPreview(
      draggedKey: "n3",
      targetKey: "n2",
      gapBelowTarget: false,
    );
    // A freshly-(re)started ticker's FIRST tick reports elapsed zero, so
    // pump once to arm the preview ticker, then advance: the slide lands
    // mid-decay and the preview mid-open on the SAME rows.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Teeth sanity: the state must genuinely exceed the max-based bound,
    // otherwise this case no longer pins the summed bound.
    expect(
      _maxComposedAbsDelta(controller),
      greaterThan(controller.maxActiveSlideAbsDelta + 5.0),
      reason: "setup: some row must carry same-sign FLIP + preview deltas "
          "whose sum exceeds the max of the engine maxima — re-engineer "
          "the overlap if this fails",
    );
    sliver.findRowAtPaintedY(100.0);
    expect(sliver.debugLastFindRowUsedFullScan, isFalse,
        reason: "setup: the FLIP+preview overlap must still route to the "
            "bounded scan (no ghosts in a fully-visible tree) — this is "
            "the state the summed bound exists for");
    _expectOracleEquivalence(sliver, controller, "FLIP+preview overlap");
    await tester.pumpAndSettle();

    // S3: pending-deletion rows mid-exit under a held preview.
    controller.setReorderPreview(
      draggedKey: "n2",
      targetKey: "n0",
      gapBelowTarget: false,
    );
    controller.remove(key: "n5", animate: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    _expectOracleEquivalence(sliver, controller, "pending-deletion mid-exit");
    await tester.pumpAndSettle();

    // S4: dead trailing row + past-the-end probes (fallback paths:
    // phase-1 lastLive, and the downward walk when the seed row is dead).
    controller.remove(key: "n3", animate: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    _expectOracleEquivalence(sliver, controller, "dead trailing row",
        from: 250.0, to: 5000.0, step: 50.0);
    await tester.pumpAndSettle();

    controller.clearReorderPreview(animate: false);
    await tester.pumpAndSettle();
  });

  testWidgets(
      "routing pins: bounded in steady state, full scan while a mutation "
      "is un-laid-out, bounded again after the pump", (tester) async {
    final controller = _controller(tester);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();
    final sliver = _sliver(tester);

    controller.setReorderPreview(
      draggedKey: "n1",
      targetKey: "n3",
      gapBelowTarget: true,
    );
    await tester.pumpAndSettle();

    sliver.findRowAtPaintedY(100.0);
    expect(sliver.debugLastFindRowUsedFullScan, isFalse,
        reason: "settled preview, no ghosts, offsets fresh → bounded scan");

    // Structural mutation with NO pump: layout-stamped offsets are stale,
    // the routing must take the exact full scan (which reads controller
    // truth) — and its result must still match the oracle trivially.
    controller.insertRoot(
      TreeNode(key: "n99", data: "N99"),
      index: 0,
      animate: false,
    );
    final duringStale = sliver.findRowAtPaintedY(100.0);
    expect(sliver.debugLastFindRowUsedFullScan, isTrue,
        reason: "un-laid-out structural mutation → full-scan route");
    final oracle = sliver.debugFindRowFullScan(100.0);
    expect(duringStale!.key, oracle!.key);

    await tester.pump();
    sliver.findRowAtPaintedY(100.0);
    expect(sliver.debugLastFindRowUsedFullScan, isFalse,
        reason: "after the mutation is laid out, the bounded scan "
            "resumes");

    controller.clearReorderPreview(animate: false);
    await tester.pumpAndSettle();
  });

  testWidgets(
      "window-size pin: steady drag over a 1000-row order examines "
      "O(window) rows, not O(N)", (tester) async {
    // Ghost-free by construction: no commit precedes the drag, so no
    // FLIP slides and no edge ghosts exist (a held preview RETAINS
    // settled ghosts — see the ghost-prune note in the routing doc — so
    // starting ghost-free is a test requirement, not a nicety).
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      for (int i = 0; i < 1000; i++) TreeNode(key: "n$i", data: "N$i"),
    ]);
    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();
    final sliver = _sliver(tester);

    // Single-row dragged block → D = one row's lift; the window around
    // any probe covers a handful of rows.
    controller.setReorderPreview(
      draggedKey: "n2",
      targetKey: "n6",
      gapBelowTarget: false,
    );

    final hit = sliver.findRowAtPaintedY(100.0);
    expect(hit, isNotNull);
    expect(sliver.debugLastFindRowUsedFullScan, isFalse,
        reason: "setup: the pin is only meaningful on the bounded route");
    expect(
      sliver.debugLastFindRowIterationCount,
      lessThanOrEqualTo(10),
      reason: "the bounded scan must examine only the ±lift window "
          "around the probe (a ~40px lift over ~30-48px rows), not the "
          "1000-row order — a larger count means the routing or the "
          "window bound regressed",
    );

    controller.clearReorderPreview(animate: false);
  });
}
