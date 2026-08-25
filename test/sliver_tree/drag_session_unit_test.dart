/// Headless unit tests for the drag-session collaborators
/// (`_drag_session.dart` / `_drag_session_behaviors.dart` — plan
/// `plans/drag_session_collaborators_2026_07_28_plan.md`).
///
/// [DragProbe] owns grab geometry and the resolution core; both are pure
/// functions of scripted [ReorderRenderPort] rows + samples, so the
/// capture table runs WITHOUT mounting a widget tree. [TestVSync]
/// provides the [TickerProvider] the [TreeController] constructor
/// requires (house precedent: `layout_admission_policy_test.dart`).
/// [AutoScroller.velocityAt] is pure. [PointerSpace] and the
/// [DwellExpander] fake-clock tests use `testWidgets` only for a real
/// [ScrollableState] / the fake [Timer] clock — no [SliverTree] mounts.
library;

import 'package:widgets_extended/sliver_tree/animation_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/_drag_session.dart';
import 'package:widgets_extended/sliver_tree/_drag_session_behaviors.dart';
import 'package:widgets_extended/sliver_tree/_drop_zone_resolver.dart';
import 'package:widgets_extended/sliver_tree/reorder_render_port.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

/// Scripted port: rows are (key, paintedOffset, extent) tuples; the
/// lookup mirrors `RenderSliverTree.findRowAtPaintedY`'s contract
/// (containing range, last-row fallback past the bottom). Records every
/// requested scrollY so tests can pin WHERE the probe looked.
class _FakeRenderPort implements ReorderRenderPort<String> {
  _FakeRenderPort(
    this.rows, {
    this.precedingScrollExtent = 0.0,
    this.pinned = const <String, ({double paintedOffset, double extent})>{},
  });

  final List<({String key, double paintedOffset, double extent})> rows;

  /// Painted bands that differ from the positional script, modelling
  /// sticky-pinned headers: a pinned header paints at its pinned band
  /// while its structural offset has scrolled away above.
  final Map<String, ({double paintedOffset, double extent})> pinned;
  final List<double> lookups = <double>[];

  @override
  bool get isLaidOut => true;

  @override
  final double precedingScrollExtent;

  @override
  bool drivesController(Object treeController) {
    return true;
  }

  /// Key-addressed inverse of [findRowAtPaintedY]. Deliberately does
  /// NOT record into [lookups]: that list pins WHERE the probe looked
  /// positionally, and grab capture no longer looks positionally.
  @override
  ({String key, double paintedOffset, double extent})? findPinnedRowAtPaintedY(
    double scrollY,
  ) {
    return null;
  }

  @override
  ({double paintedOffset, double extent})? paintedRowBounds(String key) {
    final pin = pinned[key];
    if (pin != null) {
      return pin;
    }
    for (final row in rows) {
      if (row.key == key) {
        return (paintedOffset: row.paintedOffset, extent: row.extent);
      }
    }
    return null;
  }

  @override
  ({String key, double paintedOffset, double extent})? findRowAtPaintedY(
    double scrollY,
  ) {
    lookups.add(scrollY);
    if (rows.isEmpty || scrollY < 0) {
      return null;
    }
    for (final row in rows) {
      if (scrollY >= row.paintedOffset &&
          scrollY < row.paintedOffset + row.extent) {
        return row;
      }
    }
    final last = rows.last;
    if (scrollY >= last.paintedOffset + last.extent) {
      return last;
    }
    return null;
  }

  @override
  void pinNode(String key) {}

  @override
  void unpinNode(String key) {}

  @override
  void beginSlideBaseline({
    required Duration duration,
    required Curve curve,
    Map<String, ({double y, double? x})>? baselineOverrides,
  }) {}
}

PointerSample _sampleAt(double sliverY, {double sliverX = 0.0}) {
  return (
    sliverX: sliverX,
    sliverY: sliverY,
    viewportDy: sliverY,
    viewportHeight: 600.0,
  );
}

void main() {
  // Three 50px rows: a (0..50), b (50..100), c (100..150).
  List<({String key, double paintedOffset, double extent})> threeRows() {
    return <({String key, double paintedOffset, double extent})>[
      (key: "a", paintedOffset: 0.0, extent: 50.0),
      (key: "b", paintedOffset: 50.0, extent: 50.0),
      (key: "c", paintedOffset: 100.0, extent: 50.0),
    ];
  }

  group("DragProbe capture table", () {
    late TreeController<String, String> controller;
    late DropZoneResolver<String> resolver;

    setUp(() {
      controller = TreeController<String, String>(
        vsync: const TestVSync(),
        animationStyle: TreeAnimationStyle.disabled,
      );
      controller.setRoots(const [
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ]);
      resolver = DropZoneResolver<String>(treeController: controller);
    });

    tearDown(() {
      controller.dispose();
    });

    DragProbe<String> probeOver(
      _FakeRenderPort port, {
      String draggedKey = "b",
    }) {
      return DragProbe<String>(
        renderPort: port,
        resolver: resolver,
        draggedKey: draggedKey,
        depthForPointerX: null,
      );
    }

    test("success: grab captured within the dragged row, probe gated on", () {
      final probe = probeOver(_FakeRenderPort(threeRows()));
      // Grab row b (50..100) at sliverY 62 → 12px into the row.
      probe.captureGrab(start: _sampleAt(62.0), midpointProbe: true);

      expect(probe.grabDy, 12.0);
      expect(probe.grabRowExtent, 50.0);
      // Midpoint probe: extent/2 − grabDy = 25 − 12.
      expect(probe.probeDy, 13.0);
    });

    test("gate-off: successful capture, midpointProbe false → probeDy 0", () {
      final probe = probeOver(_FakeRenderPort(threeRows()));
      probe.captureGrab(start: _sampleAt(62.0), midpointProbe: false);

      expect(probe.grabDy, 12.0);
      expect(probe.grabRowExtent, 50.0);
      expect(probe.probeDy, 0.0);
    });

    test(
      "pointer above the dragged row: clamps against the row's OWN band",
      () {
        // Rewritten when grab capture moved from a positional lookup to a
        // key-addressed one. It used to assert the "distrust" fallback: a
        // positional lookup that returned a DIFFERENT key meant the geometry
        // was untrustworthy, so grabDy went to 0, the FOREIGN row's extent
        // was reported, and the midpoint probe was suppressed.
        //
        // Asking by key removes that category entirely. There is no wrong
        // row to resolve any more, so the answer below is trustworthy: the
        // pointer is above b, grabDy clamps to b's top, and the extent is
        // b's own. The probe therefore applies, where it previously could
        // not. Strictly better geometry, and the reason the old expectations
        // are gone rather than preserved.
        final probe = probeOver(_FakeRenderPort(threeRows()));
        // Dragging b (50..100), but the start sample sits at 10.
        probe.captureGrab(start: _sampleAt(10.0), midpointProbe: true);

        expect(probe.grabDy, 0.0);
        expect(probe.grabRowExtent, 50.0, reason: "b's extent, not a's");
        expect(
          probe.probeDy,
          25.0,
          reason: "trustworthy capture, probe applies",
        );
      },
    );

    test("REPRO: a sticky-pinned row captures against its PAINTED band", () {
      // The bug. A pinned header paints at its pinned band while its
      // structural offset has scrolled away above, so asking
      // findRowAtPaintedY what sits at the pinned strip returns whatever
      // content is scrolled UNDERNEATH it. The key comparison then failed
      // and capture silently fell back to a top anchor carrying a foreign
      // extent.
      //
      // Modelled here exactly as the render layer produces it: "b" is
      // pinned at 0..32 (a 32px header), while the positional script still
      // reports the 50px content rows at their structural offsets.
      final port = _FakeRenderPort(
        threeRows(),
        pinned: const <String, ({double paintedOffset, double extent})>{
          "b": (paintedOffset: 0.0, extent: 32.0),
        },
      );
      final probe = probeOver(port);

      // Setup sanity: positionally, y=20 is row "a", NOT the dragged "b".
      // Without this the test could pass for the trivial reason that the
      // two lookups happened to agree.
      expect(port.findRowAtPaintedY(20.0)?.key, "a");

      // Grab the pinned header 20px down from its painted top.
      probe.captureGrab(start: _sampleAt(20.0), midpointProbe: true);

      expect(
        probe.grabDy,
        20.0,
        reason: "held where grabbed, not snapped to the row's top",
      );
      expect(
        probe.grabRowExtent,
        32.0,
        reason: "the header's own extent, not the row scrolled beneath it",
      );
      expect(
        probe.probeDy,
        -4.0,
        reason: "midpoint probe stays live: 32/2 - 20",
      );
    });

    test("no row at all: zeroed grab record, no probe shift", () {
      final probe = probeOver(
        _FakeRenderPort(
          <({String key, double paintedOffset, double extent})>[],
        ),
      );
      probe.captureGrab(start: _sampleAt(10.0), midpointProbe: true);

      expect(probe.grabDy, 0.0);
      expect(probe.grabRowExtent, 0.0);
      expect(probe.probeDy, 0.0);
    });

    test("clamp: past-the-bottom fallback resolves the last row and clamps "
        "grabDy to its extent", () {
      final probe = probeOver(_FakeRenderPort(threeRows()), draggedKey: "c");
      // 175 is past c's bottom (150); the port's last-row fallback
      // reports c, and raw dy (175 − 100 = 75) exceeds the 50px extent.
      probe.captureGrab(start: _sampleAt(175.0), midpointProbe: true);

      expect(probe.grabDy, 50.0);
      expect(probe.grabRowExtent, 50.0);
      // Gate still applies to the clamped capture: 25 − 50.
      expect(probe.probeDy, -25.0);
    });
  });

  group("DragProbe resolveTarget", () {
    late TreeController<String, String> controller;
    late DropZoneResolver<String> resolver;

    setUp(() {
      controller = TreeController<String, String>(
        vsync: const TestVSync(),
        animationStyle: TreeAnimationStyle.disabled,
      );
      controller.setRoots(const [
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ]);
      resolver = DropZoneResolver<String>(treeController: controller);
    });

    tearDown(() {
      controller.dispose();
    });

    test("null sample: returns the previous target unchanged (hold)", () {
      final probe = DragProbe<String>(
        renderPort: _FakeRenderPort(threeRows()),
        resolver: resolver,
        draggedKey: "b",
        depthForPointerX: null,
      );
      const previous = TreeDropTarget<String>(
        targetKey: "a",
        zone: TreeDropZone.above,
        parentKey: null,
        indexInFinalList: 0,
        depth: 0,
        gapVisibleIndex: 0,
        targetPaintedY: 0.0,
        targetExtent: 50.0,
      );

      final held = probe.resolveTarget(sample: null, previous: previous);

      expect(identical(held, previous), isTrue);
    });

    test("no hovered row: resolves to null (not held)", () {
      final probe = DragProbe<String>(
        renderPort: _FakeRenderPort(threeRows()),
        resolver: resolver,
        draggedKey: "b",
        depthForPointerX: null,
      );
      const previous = TreeDropTarget<String>(
        targetKey: "a",
        zone: TreeDropZone.above,
        parentKey: null,
        indexInFinalList: 0,
        depth: 0,
        gapVisibleIndex: 0,
        targetPaintedY: 0.0,
        targetExtent: 50.0,
      );

      // Negative sliverY: the scripted port reports no row there.
      final target = probe.resolveTarget(
        sample: _sampleAt(-10.0),
        previous: previous,
      );

      expect(target, isNull);
    });

    test("probes at sliverY + probeDy while the depth hint keeps the RAW "
        "pointer x", () {
      final port = _FakeRenderPort(threeRows());
      final seenX = <double>[];
      final probe = DragProbe<String>(
        renderPort: port,
        resolver: resolver,
        draggedKey: "b",
        depthForPointerX: (double sliverLocalX) {
          seenX.add(sliverLocalX);
          return 0;
        },
      );
      probe.captureGrab(start: _sampleAt(62.0), midpointProbe: true);
      expect(probe.probeDy, 13.0);
      port.lookups.clear();

      final target = probe.resolveTarget(
        sample: _sampleAt(120.0, sliverX: 7.0),
        previous: null,
      );

      // Row lookup happened at the SHIFTED y (120 + 13), not the raw y.
      expect(port.lookups, <double>[133.0]);
      // 133 lands in row c (100..150); the resolver classified c.
      expect(target, isNotNull);
      expect(target!.targetKey, "c");
      // The x-depth hint received the raw pointer x — the vertical probe
      // shift never touches horizontal.
      expect(seenX, <double>[7.0]);
    });
  });

  group("AutoScroller.velocityAt", () {
    const zone = 48.0;
    const max = 1200.0;
    const height = 600.0;

    double at(double dy) {
      return AutoScroller.velocityAt(
        viewportDy: dy,
        viewportHeight: height,
        edgeZone: zone,
        maxVelocity: max,
      );
    }

    test("dead center and both zone boundaries are 0", () {
      expect(at(300.0), 0.0);
      // Boundaries are EXCLUSIVE: the ramp starts strictly inside the
      // zone, so a pointer exactly at the boundary does not scroll.
      expect(at(zone), 0.0);
      expect(at(height - zone), 0.0);
    });

    test("linear ramp: half-zone gives half velocity, edge gives max", () {
      expect(at(24.0), -600.0);
      expect(at(0.0), -max);
      expect(at(height - 24.0), 600.0);
      expect(at(height), max);
    });

    test("overshoot past the viewport clamps to max velocity", () {
      // A captured pointer can report positions outside the viewport.
      expect(at(-50.0), -max);
      expect(at(height + 80.0), max);
    });
  });

  group("PointerSpace", () {
    Widget scrollableApp() {
      return MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (int i = 0; i < 30; i++)
                SizedBox(height: 50.0, child: Text("row $i")),
            ],
          ),
        ),
      );
    }

    testWidgets("sample converts global → sliver-local + viewport coords", (
      tester,
    ) async {
      await tester.pumpWidget(scrollableApp());
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      final space = PointerSpace<String>(
        scrollable: scrollable,
        renderPort: _FakeRenderPort(threeRows(), precedingScrollExtent: 40.0),
      );

      expect(space.isLive, isTrue);
      expect(space.position, isNotNull);

      final sample = space.sample(const Offset(100.0, 250.0));
      expect(sample, isNotNull);
      // Fullscreen viewport at the origin: local == global.
      expect(sample!.sliverX, 100.0);
      expect(sample.viewportDy, 250.0);
      expect(sample.viewportHeight, 600.0);
      // pixels (0) + localDy (250) − precedingScrollExtent (40).
      expect(sample.sliverY, 210.0);
    });

    testWidgets("sample tracks the live scroll offset", (tester) async {
      await tester.pumpWidget(scrollableApp());
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      final space = PointerSpace<String>(
        scrollable: scrollable,
        renderPort: _FakeRenderPort(threeRows(), precedingScrollExtent: 40.0),
      );

      scrollable.position.jumpTo(120.0);
      await tester.pump();

      final sample = space.sample(const Offset(100.0, 250.0));
      // pixels (120) + localDy (250) − precedingScrollExtent (40).
      expect(sample!.sliverY, 330.0);
    });

    testWidgets("defunct scrollable: isLive false, position and sample null", (
      tester,
    ) async {
      await tester.pumpWidget(scrollableApp());
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      final space = PointerSpace<String>(
        scrollable: scrollable,
        renderPort: _FakeRenderPort(threeRows()),
      );
      // Sanity: live before the swap.
      expect(space.sample(const Offset(0.0, 0.0)), isNotNull);

      // Swap the whole tree out — the ScrollableState unmounts. Reading
      // `.context`/`.position` on it would assert; the nullable reads
      // are the contract that makes that impossible to hit.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      expect(space.isLive, isFalse);
      expect(space.position, isNull);
      expect(space.sample(const Offset(0.0, 0.0)), isNull);
    });

    // M25, mechanism (i): with no widget layer above the controller, the
    // subscription must still follow a ScrollPosition swap, and the only
    // hook a headless session has is its own sample.
    testWidgets("bindScroll follows a ScrollPosition swap on the next sample", (
      tester,
    ) async {
      final physics = ValueNotifier<ScrollPhysics>(
        const ClampingScrollPhysics(),
      );
      addTearDown(physics.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<ScrollPhysics>(
              valueListenable: physics,
              builder: (context, value, child) {
                return ListView(
                  physics: value,
                  children: [
                    for (int i = 0; i < 30; i++)
                      SizedBox(height: 50.0, child: Text("row $i")),
                  ],
                );
              },
            ),
          ),
        ),
      );
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      final space = PointerSpace<String>(
        scrollable: scrollable,
        renderPort: _FakeRenderPort(threeRows()),
      );
      var notifications = 0;
      space.bindScroll(() => notifications++);
      final before = scrollable.position;
      before.jumpTo(10.0);
      expect(
        notifications,
        1,
        reason: "setup sanity: the listener sits on the current position",
      );

      physics.value = const NeverScrollableScrollPhysics();
      await tester.pump();
      final after = scrollable.position;
      expect(
        identical(before, after),
        isFalse,
        reason:
            "setup sanity: a physics runtimeType change must swap the "
            "position",
      );

      space.sample(const Offset(0.0, 0.0));
      after.jumpTo(20.0);
      expect(
        notifications,
        2,
        reason:
            "sample() must re-point the subscription at the live position; "
            "a listener left on the swapped-out position never fires again",
      );

      space.unbindScroll();
      after.jumpTo(30.0);
      expect(
        notifications,
        2,
        reason: "unbindScroll must detach from the live position",
      );
    });
  });

  group("DwellExpander fake-clock", () {
    const delay = Duration(milliseconds: 500);

    late TreeController<String, String> controller;
    late bool live;
    late int resolveCount;

    setUp(() {
      live = true;
      resolveCount = 0;
    });

    DwellExpander<String> makeDwell({Duration? dwellDelay = delay}) {
      return DwellExpander<String>(
        treeController: controller,
        delay: dwellDelay,
        sessionLive: () => live,
        requestResolve: () => resolveCount++,
      );
    }

    /// Collapsed parent "p" (one child), leaf root "x".
    void seedTree(WidgetTester tester) {
      controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots(const [
        TreeNode(key: "p", data: "P"),
        TreeNode(key: "x", data: "X"),
      ]);
      controller.setChildren("p", const [TreeNode(key: "c", data: "C")]);
      // Setup sanity: the arming predicate's exact preconditions.
      expect(controller.isExpanded("p"), isFalse);
      expect(controller.hasLiveChildren("p"), isTrue);
    }

    TreeDropTarget<String> into(String key) {
      return TreeDropTarget<String>(
        targetKey: key,
        zone: TreeDropZone.into,
        parentKey: key,
        indexInFinalList: 0,
        depth: 1,
        gapVisibleIndex: 1,
        targetPaintedY: 0.0,
        targetExtent: 50.0,
      );
    }

    testWidgets("arms on into+collapsed+children, expands after the delay", (
      tester,
    ) async {
      seedTree(tester);
      final dwell = makeDwell();

      dwell.onTargetResolved(into("p"));
      expect(controller.isExpanded("p"), isFalse);

      await tester.pump(delay + const Duration(milliseconds: 1));

      expect(controller.isExpanded("p"), isTrue);
      // The fire re-resolves through the controller's async re-entry.
      expect(resolveCount, 1);
    });

    testWidgets("re-delivering the SAME candidate leaves the timer running", (
      tester,
    ) async {
      seedTree(tester);
      final dwell = makeDwell();

      dwell.onTargetResolved(into("p"));
      await tester.pump(const Duration(milliseconds: 300));
      // Fresh but equal target instance — every pointer move re-delivers.
      dwell.onTargetResolved(into("p"));
      // 300 + 250 passes the ORIGINAL deadline; a reset timer would
      // still have 250ms to go.
      await tester.pump(const Duration(milliseconds: 250));

      expect(controller.isExpanded("p"), isTrue);
    });

    testWidgets("moving off the candidate disarms", (tester) async {
      seedTree(tester);
      final dwell = makeDwell();

      dwell.onTargetResolved(into("p"));
      await tester.pump(const Duration(milliseconds: 300));
      dwell.onTargetResolved(null);
      await tester.pump(const Duration(seconds: 2));

      expect(controller.isExpanded("p"), isFalse);
      expect(resolveCount, 0);
    });

    testWidgets("non-arming targets: leaf, already-expanded, non-into zone", (
      tester,
    ) async {
      seedTree(tester);
      final dwell = makeDwell();

      // Leaf: no live children to reveal.
      dwell.onTargetResolved(into("x"));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.isExpanded("x"), isFalse);

      // Non-into zone on an armable key.
      dwell.onTargetResolved(
        const TreeDropTarget<String>(
          targetKey: "p",
          zone: TreeDropZone.above,
          parentKey: null,
          indexInFinalList: 0,
          depth: 0,
          gapVisibleIndex: 0,
          targetPaintedY: 0.0,
          targetExtent: 50.0,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(controller.isExpanded("p"), isFalse);

      // Already expanded: nothing to do.
      controller.expand(key: "p");
      dwell.onTargetResolved(into("p"));
      await tester.pump(const Duration(seconds: 1));
      expect(resolveCount, 0);
    });

    testWidgets("dead session at fire time: no expand, no re-resolve", (
      tester,
    ) async {
      seedTree(tester);
      final dwell = makeDwell();

      dwell.onTargetResolved(into("p"));
      live = false;
      await tester.pump(const Duration(seconds: 1));

      expect(controller.isExpanded("p"), isFalse);
      expect(resolveCount, 0);
    });

    testWidgets("detach cancels the armed timer", (tester) async {
      seedTree(tester);
      final dwell = makeDwell();

      dwell.onTargetResolved(into("p"));
      dwell.detach(SessionExit.cancel);
      await tester.pump(const Duration(seconds: 2));

      expect(controller.isExpanded("p"), isFalse);
      expect(resolveCount, 0);
    });

    testWidgets("null delay disables arming entirely", (tester) async {
      seedTree(tester);
      final dwell = makeDwell(dwellDelay: null);

      dwell.onTargetResolved(into("p"));
      await tester.pump(const Duration(seconds: 2));

      expect(controller.isExpanded("p"), isFalse);
    });
  });
}
