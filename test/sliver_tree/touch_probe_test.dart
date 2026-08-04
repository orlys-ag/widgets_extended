/// Touch-first probe tests (plan T1/T2/T4,
/// `plans/touch_first_drag_probe_2026_07_27_plan.md`).
///
/// In make-room + proxy sessions, slot resolution probes at the PROXY
/// MIDPOINT (`pointer + probeDy`, `probeDy = rowExtent/2 − grabDy`,
/// captured once at drag start) instead of the raw pointer — on touch
/// there is no visible cursor, so the card in hand is the only thing the
/// user can steer by.
///
/// Repro-test methodology: the flip-point, commit-inheritance, and dwell
/// tests FAIL on pointer-probe code (by exactly δ); the T4 pins pass
/// before AND after (they exist so the gate and the δ≈0 equivalence can
/// never rot silently).
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Mixed-size harness: the DRAGGED row r0 is 100px tall, the rest 50px —
/// maximal probe offsets. Flat-list policy (`newParent == null`) so
/// crossed rows use the two-zone MIDPOINT split (plan F2: the
/// `flipY = rowMid − probeDy` math only holds there).
Future<({TreeController<String, String> tree, TreeReorderController<String> reorder})>
    _mount(
  WidgetTester tester, {
  bool proxy = true,
  bool flatPolicy = true,
  Map<String, double> heights = const {"r0": 100.0},
}) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  tree.setRoots([
    for (var i = 0; i < 5; i++) TreeNode(key: "r$i", data: "R$i"),
  ]);
  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
    canAcceptDrop: flatPolicy
        ? ({required movingKey, newParent, index}) => newParent == null
        : null,
  );
  addTearDown(() {
    if (reorder.isDragging) {
      reorder.cancelDrag();
    }
    reorder.dispose();
    tree.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
              showDragProxy: proxy,
              nodeBuilder: (context, key, depth, wrap) {
                return wrap(
                  longPressToDrag: true,
                  child: SizedBox(
                    key: ValueKey("row-$key"),
                    height: heights[key] ?? 50.0,
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
  await tester.pumpAndSettle();
  return (tree: tree, reorder: reorder);
}

/// Long-presses at [grabGlobal] and returns the active gesture.
Future<TestGesture> _lift(WidgetTester tester, Offset grabGlobal) async {
  final gesture = await tester.startGesture(grabGlobal);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  return gesture;
}

void main() {
  // ─── T1: flip point follows the proxy midpoint ─────────────────────────
  // Rows: r0 [0,100), r1 [100,150), r2 [150,200)... TOP-grab r0 at y=5:
  // grabDy = 5, probeDy = 50 − 5 = 45. The current-position → below-r1
  // flip sits at probe = r1 midpoint (125) ⇒ pointer flipY = 125 − 45 = 80.
  testWidgets(
    "T1: TOP-grabbed tall card flips at rowMid − probeDy, not at the "
    "pointer's own crossing",
    (tester) async {
      final h = await _mount(tester);
      final gesture = await _lift(tester, const Offset(400, 5));
      expect(h.reorder.isDragging, isTrue, reason: "setup: lifted");
      expect(h.reorder.dragProxyGeometry?.grabDy, 5.0,
          reason: "setup: top grab");

      // A3 setup invariant: the probe starts at the dragged row's OWN
      // midpoint regardless of grab point → current-position target.
      expect(h.reorder.currentTarget?.indexInFinalList, 0,
          reason: "A3: every gated session begins at current position");

      // Just before the flip (pointer 78 → probe 123 < 125).
      await gesture.moveTo(const Offset(400, 78));
      await tester.pump();
      expect(h.reorder.currentTarget?.indexInFinalList, 0,
          reason: "probe 123 is above r1's midpoint — still 'returns "
              "here'");

      // Just after (pointer 82 → probe 127 ≥ 125). On pointer-probe code
      // the pointer (82) is still deep inside r0's own band — this is the
      // repro assertion that fails by exactly δ pre-T1.
      await gesture.moveTo(const Offset(400, 82));
      await tester.pump();
      expect(h.reorder.currentTarget?.indexInFinalList, 1,
          reason: "the CARD's midpoint crossed r1's midpoint — the slot "
              "must flip even though the pointer is far above");

      // Stability under the make-room shift the flip triggered.
      await tester.pump();
      expect(h.reorder.currentTarget?.indexInFinalList, 1,
          reason: "the flipped slot is stable against its own shift");

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "T1 mirror: BOTTOM-grabbed card flips δ later in pointer terms",
    (tester) async {
      final h = await _mount(tester);
      // Grab r0 at y=95: grabDy = 95, probeDy = 50 − 95 = −45 → flip
      // pointer y = 125 + 45 = 170.
      final gesture = await _lift(tester, const Offset(400, 95));
      expect(h.reorder.dragProxyGeometry?.grabDy, 95.0,
          reason: "setup: bottom grab");
      expect(h.reorder.currentTarget?.indexInFinalList, 0,
          reason: "A3: starts at current position");

      await gesture.moveTo(const Offset(400, 168));
      await tester.pump();
      expect(h.reorder.currentTarget?.indexInFinalList, 0,
          reason: "pointer 168 → probe 123: the card has NOT overlapped "
              "half of r1 yet, even though the pointer is well past it");

      await gesture.moveTo(const Offset(400, 172));
      await tester.pump();
      expect(h.reorder.currentTarget?.indexInFinalList, 1,
          reason: "pointer 172 → probe 127: the card's midpoint crossed");

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "T1 (A1): the commit lands the midpoint-probe slot when pointer and "
    "midpoint disagree",
    (tester) async {
      final h = await _mount(tester);
      final gesture = await _lift(tester, const Offset(400, 5));
      // Pointer 82: midpoint-probe slot = 1; pointer-probe slot would be
      // the current position (a settle-back, committing nothing).
      await gesture.moveTo(const Offset(400, 82));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(h.tree.liveRootKeys, ["r1", "r0", "r2", "r3", "r4"],
          reason: "feedback and commit must agree: the drop commits the "
              "slot the gap showed (index 1), not a pointer-derived "
              "no-op");
    },
  );

  testWidgets(
    "T1: mixed-size sweep resolves a slot at every step, monotonically",
    (tester) async {
      final h = await _mount(
        tester,
        heights: const {"r0": 100.0, "r2": 80.0, "r4": 100.0},
      );
      final gesture = await _lift(tester, const Offset(400, 10));

      final slots = <int>[];
      var sawNull = false;
      for (double y = 10; y <= 330; y += 5) {
        await gesture.moveTo(Offset(400, y));
        await tester.pump();
        final target = h.reorder.currentTarget;
        if (target == null) {
          sawNull = true;
          continue;
        }
        expect(target.parentKey, isNull,
            reason: "flat policy: every slot is root-level");
        slots.add(target.indexInFinalList);
      }

      expect(sawNull, isFalse,
          reason: "no dead spots anywhere in the sweep");
      for (var i = 1; i < slots.length; i++) {
        expect(slots[i] >= slots[i - 1], isTrue,
            reason: "slot sequence must be non-decreasing sweeping down "
                "(${slots[i - 1]} → ${slots[i]} at step $i) — an A↔B↔A "
                "alternation is the oscillation class the boundary fixes "
                "killed");
      }

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );

  // ─── T2: into/dwell follow the SAME probe ──────────────────────────────
  testWidgets(
    "T2: dwell fires when the CARD MIDPOINT hovers a collapsed parent "
    "while the pointer is elsewhere",
    (tester) async {
      // No flat policy: the `into` band must exist.
      final h = await _mount(tester, flatPolicy: false);
      h.tree.setChildren("r1", [const TreeNode(key: "c1", data: "C1")]);
      await tester.pumpAndSettle();
      expect(h.tree.isExpanded("r1"), isFalse, reason: "setup: collapsed");

      final gesture = await _lift(tester, const Offset(400, 5));
      // Pointer 80 → probe 125 = the exact center of collapsed r1's band
      // [100,150) — inside its into third. The POINTER is still over r0.
      await gesture.moveTo(const Offset(400, 80));
      await tester.pump();
      expect(h.reorder.currentTarget?.zone, TreeDropZone.into,
          reason: "setup: the card's midpoint targets into-r1");
      expect(h.reorder.currentTarget?.targetKey, "r1");

      await tester.pump(const Duration(milliseconds: 800));
      expect(h.tree.isExpanded("r1"), isTrue,
          reason: "the dwell must key off the card's midpoint — on touch "
              "the card IS the aim");

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "T2 mirror: pointer over the collapsed parent but midpoint elsewhere "
    "does NOT arm the dwell",
    (tester) async {
      final h = await _mount(tester, flatPolicy: false);
      h.tree.setChildren("r1", [const TreeNode(key: "c1", data: "C1")]);
      await tester.pumpAndSettle();

      final gesture = await _lift(tester, const Offset(400, 5));
      // Pointer 125 sits on r1 — but the probe (170) is over r2.
      await gesture.moveTo(const Offset(400, 125));
      await tester.pump();
      expect(h.reorder.currentTarget?.targetKey, isNot("r1"),
          reason: "setup: the probe left r1 behind");

      await tester.pump(const Duration(milliseconds: 800));
      expect(h.tree.isExpanded("r1"), isFalse,
          reason: "the finger's position must not arm a dwell the card "
              "is not making");

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );

  // ─── T4: equivalence and gate pins (pass before AND after T1) ──────────
  testWidgets(
    "T4 pin: handle drags are δ≈0 — flip at the raw row midpoint",
    (tester) async {
      final tree = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      tree.setRoots([
        for (var i = 0; i < 4; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
        canAcceptDrop: ({required movingKey, newParent, index}) =>
            newParent == null,
      );
      addTearDown(() {
        if (reorder.isDragging) {
          reorder.cancelDrag();
        }
        reorder.dispose();
        tree.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverReorderableTree<String, String>(
                  controller: tree,
                  reorderController: reorder,
                  showDragProxy: true,
                  nodeBuilder: (context, key, depth, wrap) {
                    return wrap(
                      handle: Icon(Icons.drag_indicator,
                          key: ValueKey("h-$key")),
                      child: SizedBox(
                        key: ValueKey("row-$key"),
                        height: 50,
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
      await tester.pumpAndSettle();

      // Handle is vertically centered → grabDy ≈ 25 on a 50px row →
      // probeDy ≈ 0 → the flip sits at r1's raw midpoint (75), exactly
      // as before T1.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey("h-r0"))),
      );
      // Past the touch slop so the vertical-drag recognizer accepts; with
      // DragStartBehavior.down the reported grab stays the DOWN position.
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      expect(reorder.dragProxyGeometry?.grabDy, closeTo(25.0, 1.0),
          reason: "pin: handle grabs are centered by construction");

      await gesture.moveTo(const Offset(400, 73));
      await tester.pump();
      expect(reorder.currentTarget?.indexInFinalList, 0,
          reason: "pin: below r1's midpoint not yet crossed");
      await gesture.moveTo(const Offset(400, 77));
      await tester.pump();
      expect(reorder.currentTarget?.indexInFinalList, 1,
          reason: "pin: handle-drag flip point is unchanged by T1");

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "T4 pin: proxy WITHOUT make-room keeps the raw pointer probe",
    (tester) async {
      // No longer expressible through SliverReorderableTree — make-room is
      // unconditional there — so drive the controller directly. The shift
      // is gated on make-room AND settle-from-release; this pins that it
      // really is an AND.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      final port = _FakePort(controller: controller);
      final reorder = TreeReorderController<String>(
        treeController: controller,
        vsync: tester,
        // Flat-list policy so crossed rows take the two-zone MIDPOINT
        // split — the raw/shifted discrimination below only holds there.
        canAcceptDrop: ({required movingKey, newParent, index}) =>
            newParent == null,
      );
      addTearDown(reorder.dispose);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [SliverToBoxAdapter(child: SizedBox(height: 2000))],
            ),
          ),
        ),
      );
      final scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable));

      reorder.startDrag(
        key: "a",
        renderPort: port,
        scrollable: scrollable,
        pointerGlobal: const Offset(200, 5),
        makeRoom: false,
        settleFromRelease: true,
      );
      // Rows are 50px. grabDy = 5, so a midpoint probe would sit at
      // pointer + 20. Pointer 70 → top half of b → above-b ≡ a's current
      // slot (index 0). A shifted probe (90) would read b's bottom half →
      // below-b (index 1).
      reorder.updateDrag(const Offset(200, 70));
      expect(reorder.currentTarget?.indexInFinalList, 0,
          reason: "pin: the midpoint shift needs make-room too — with only "
              "a proxy there is no card-anchored slot selection");
      reorder.cancelDrag();
    },
  );

  testWidgets(
    "T4 pin: make-room WITHOUT a proxy keeps the raw pointer probe",
    (tester) async {
      final h = await _mount(tester, proxy: false);
      final gesture = await _lift(tester, const Offset(400, 5));
      await gesture.moveTo(const Offset(400, 82));
      await tester.pump();
      expect(h.reorder.currentTarget?.indexInFinalList, 0,
          reason: "pin: with nothing floating there is no visible anchor "
              "— the probe must stay at the pointer");
      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "T4 pin: imperative startDrag with neither flag follows the raw "
    "pointer",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      final port = _FakePort(controller: controller);
      final reorder = TreeReorderController<String>(
        treeController: controller,
        vsync: tester,
      );
      addTearDown(reorder.dispose);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [SliverToBoxAdapter(child: SizedBox(height: 2000))],
            ),
          ),
        ),
      );
      final scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable));

      reorder.startDrag(
        key: "a",
        renderPort: port,
        scrollable: scrollable,
        pointerGlobal: const Offset(200, 30),
      );
      // Raw pointer at 145 → bottom of c → below-c, final index 2.
      reorder.updateDrag(const Offset(200, 145));
      expect(reorder.currentTarget?.indexInFinalList, 2,
          reason: "pin: default sessions resolve at the raw pointer");
      reorder.cancelDrag();
    },
  );
}

class _FakePort implements ReorderRenderPort<String> {
  _FakePort({required this.controller});

  final TreeController<String, String> controller;

  @override
  bool get isLaidOut {
    return true;
  }

  @override
  double get precedingScrollExtent {
    return 0.0;
  }

  @override
  bool drivesController(Object treeController) {
    return identical(controller, treeController);
  }

  @override
  ({String key, double paintedOffset, double extent})? findRowAtPaintedY(
    double scrollY,
  ) {
    if (scrollY < 50) {
      return (key: "a", paintedOffset: 0.0, extent: 50.0);
    }
    if (scrollY < 100) {
      return (key: "b", paintedOffset: 50.0, extent: 50.0);
    }
    return (key: "c", paintedOffset: 100.0, extent: 50.0);
  }

  @override
  void pinNode(String key) {}

  @override
  void unpinNode(String key) {}

  @override
  void beginSlideBaseline({
    required Duration duration,
    required Curve curve,
    Map<String, double>? baselineYOverrides,
  }) {}
}
