/// [TreeReorderController] lifecycle tests against a scripted fake
/// [ReorderRenderPort] — the coverage D1's extraction unlocks: no
/// SliverTree, no render object, no layout. The only widget mounted is a
/// bare scrollable (the controller converts pointers through the real
/// [ScrollableState]).
///
/// What is pinned here:
/// - pin/unpin pairing across start / cancel / end / dispose,
/// - the D3 `startDrag` contract (false for policy/not-laid-out, throw for
///   cross-controller misuse),
/// - `endDrag` ordering: FLIP baseline staged BEFORE the structural
///   mutation,
/// - `endDrag` re-resolution: a stale target (no row under the pointer
///   anymore) downgrades to a cancel — no baseline, no mutation.
library;

import 'package:widgets_extended/sliver_tree/animation_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/reorder_render_port.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/tree_reorder_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

/// Scripted port. `rowAt` plays the role of the render object's painted-row
/// lookup; `log` records the calls whose ordering/pairing the controller
/// must guarantee.
class _FakePort implements ReorderRenderPort<String> {
  _FakePort({required this.controller});

  final TreeController<String, String> controller;
  final List<String> log = <String>[];
  bool laidOut = true;
  bool drives = true;
  double preceding = 0.0;
  ({String key, double paintedOffset, double extent})? Function(double y)?
  rowAt;

  @override
  bool get isLaidOut {
    return laidOut;
  }

  @override
  double get precedingScrollExtent {
    return preceding;
  }

  @override
  bool drivesController(Object treeController) {
    return drives && identical(controller, treeController);
  }

  @override
  ({String key, double paintedOffset, double extent})? findRowAtPaintedY(
    double scrollY,
  ) {
    return rowAt?.call(scrollY);
  }

  @override
  void pinNode(String key) {
    log.add("pin:$key");
  }

  @override
  void unpinNode(String key) {
    log.add("unpin:$key");
  }

  @override
  void beginSlideBaseline({
    required Duration duration,
    required Curve curve,
    Map<String, double>? baselineYOverrides,
  }) {
    log.add("baseline");
  }
}

/// Mounts a bare scrollable (no tree) and returns its state. The fake port
/// supplies all row geometry, so nothing tree-shaped needs to be laid out.
Future<ScrollableState> _mountScrollable(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: 2000)),
          ],
        ),
      ),
    ),
  );
  return tester.state<ScrollableState>(find.byType(Scrollable));
}

/// Standard script: rows a/b/c at 50px each, matching a three-root tree.
({String key, double paintedOffset, double extent})? _threeRows(double y) {
  if (y < 50) {
    return (key: "a", paintedOffset: 0.0, extent: 50.0);
  }
  if (y < 100) {
    return (key: "b", paintedOffset: 50.0, extent: 50.0);
  }
  return (key: "c", paintedOffset: 100.0, extent: 50.0);
}

TreeController<String, String> _threeRootController(WidgetTester tester) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  controller.setRoots([
    const TreeNode(key: "a", data: "A"),
    const TreeNode(key: "b", data: "B"),
    const TreeNode(key: "c", data: "C"),
  ]);
  return controller;
}

void main() {
  testWidgets("start/cancel pin-unpin pairing and session surface",
      (tester) async {
    final controller = _threeRootController(tester);
    addTearDown(controller.dispose);
    final port = _FakePort(controller: controller)..rowAt = _threeRows;
    final reorder = TreeReorderController<String>(
      treeController: controller,
      vsync: tester,
    );
    addTearDown(reorder.dispose);
    final scrollable = await _mountScrollable(tester);

    expect(reorder.renderPort, isNull, reason: "no session, no port");

    final started = reorder.startDrag(
      key: "a",
      renderPort: port,
      scrollable: scrollable,
      // y=145 → bottom third of row c → a real below-c target.
      pointerGlobal: const Offset(200, 145),
    );
    expect(started, isTrue);
    expect(reorder.isDragging, isTrue);
    expect(reorder.draggedKey, "a");
    expect(reorder.renderPort, same(port),
        reason: "the session's port is exposed for presentation consumers");
    expect(reorder.currentTarget?.targetKey, "c");
    expect(port.log, ["pin:a"]);

    reorder.cancelDrag();
    expect(reorder.isDragging, isFalse);
    expect(reorder.renderPort, isNull);
    expect(port.log, ["pin:a", "unpin:a"],
        reason: "cancel must unpin exactly the dragged row");
  });

  testWidgets("startDrag returns false on a not-laid-out port (no pin)",
      (tester) async {
    final controller = _threeRootController(tester);
    addTearDown(controller.dispose);
    final port = _FakePort(controller: controller)
      ..rowAt = _threeRows
      ..laidOut = false;
    final reorder = TreeReorderController<String>(
      treeController: controller,
      vsync: tester,
    );
    addTearDown(reorder.dispose);
    final scrollable = await _mountScrollable(tester);

    final started = reorder.startDrag(
      key: "a",
      renderPort: port,
      scrollable: scrollable,
      pointerGlobal: const Offset(200, 145),
    );
    expect(started, isFalse);
    expect(reorder.isDragging, isFalse);
    expect(port.log, isEmpty, reason: "a refused start must pin nothing");
  });

  testWidgets("startDrag throws for a port driving a different controller",
      (tester) async {
    final controller = _threeRootController(tester);
    addTearDown(controller.dispose);
    final port = _FakePort(controller: controller)
      ..rowAt = _threeRows
      ..drives = false;
    final reorder = TreeReorderController<String>(
      treeController: controller,
      vsync: tester,
    );
    addTearDown(reorder.dispose);
    final scrollable = await _mountScrollable(tester);

    expect(
      () => reorder.startDrag(
        key: "a",
        renderPort: port,
        scrollable: scrollable,
        pointerGlobal: const Offset(200, 145),
      ),
      throwsA(isA<ArgumentError>()),
      reason: "cross-controller wiring is misuse, not policy",
    );
    expect(port.log, isEmpty);
  });

  testWidgets("dispose mid-session unpins the dragged row", (tester) async {
    final controller = _threeRootController(tester);
    addTearDown(controller.dispose);
    final port = _FakePort(controller: controller)..rowAt = _threeRows;
    final reorder = TreeReorderController<String>(
      treeController: controller,
      vsync: tester,
    );
    final scrollable = await _mountScrollable(tester);

    reorder.startDrag(
      key: "b",
      renderPort: port,
      scrollable: scrollable,
      pointerGlobal: const Offset(200, 145),
    );
    expect(port.log, ["pin:b"]);

    reorder.dispose();
    expect(port.log, ["pin:b", "unpin:b"],
        reason: "disposing mid-drag must release the eviction pin — a "
            "leaked pin retains the row forever");
  });

  testWidgets("endDrag stages the FLIP baseline BEFORE the mutation",
      (tester) async {
    final controller = _threeRootController(tester);
    addTearDown(controller.dispose);
    final port = _FakePort(controller: controller)..rowAt = _threeRows;
    final reorder = TreeReorderController<String>(
      treeController: controller,
      vsync: tester,
    );
    addTearDown(reorder.dispose);
    final scrollable = await _mountScrollable(tester);

    // Record the structural mutation into the same log the port writes,
    // so relative order is observable.
    void onStructuralChange() {
      port.log.add("mutation");
    }

    controller.addListener(onStructuralChange);
    addTearDown(() {
      controller.removeListener(onStructuralChange);
    });

    reorder.startDrag(
      key: "a",
      renderPort: port,
      scrollable: scrollable,
      pointerGlobal: const Offset(200, 145),
    );
    expect(reorder.currentTarget?.targetKey, "c",
        reason: "setup: below-c must be resolved before the drop");

    reorder.endDrag();

    expect(controller.liveRootKeys, ["b", "c", "a"],
        reason: "the below-c drop must commit the root reorder");
    final baselineIndex = port.log.indexOf("baseline");
    final mutationIndex = port.log.indexOf("mutation");
    expect(baselineIndex, isNot(-1));
    expect(mutationIndex, isNot(-1));
    expect(baselineIndex, lessThan(mutationIndex),
        reason: "a baseline captured AFTER the mutation would snapshot "
            "already-new offsets and produce a zero-delta (no visible "
            "slide)");
    expect(port.log.last, "unpin:a",
        reason: "the pin must be released once the session ends");
  });

  testWidgets(
      "endDrag re-resolves: a stale target downgrades to cancel (no "
      "baseline, no mutation)", (tester) async {
    final controller = _threeRootController(tester);
    addTearDown(controller.dispose);
    final port = _FakePort(controller: controller)..rowAt = _threeRows;
    final reorder = TreeReorderController<String>(
      treeController: controller,
      vsync: tester,
    );
    addTearDown(reorder.dispose);
    final scrollable = await _mountScrollable(tester);

    reorder.startDrag(
      key: "a",
      renderPort: port,
      scrollable: scrollable,
      pointerGlobal: const Offset(200, 145),
    );
    expect(reorder.currentTarget, isNotNull,
        reason: "setup: a live target must exist before it goes stale");

    // The tree emptied under the pointer between the last move and the
    // drop (server-driven update): the re-resolve in endDrag must observe
    // CURRENT state, not the stale target.
    port.rowAt = (_) {
      return null;
    };

    reorder.endDrag();

    expect(reorder.isDragging, isFalse);
    expect(controller.liveRootKeys, ["a", "b", "c"],
        reason: "no valid target at drop time — nothing may mutate");
    expect(port.log, isNot(contains("baseline")),
        reason: "a baseline staged for a drop that then cancels would "
            "block every subsequent slide stage (first-wins slot)");
    expect(port.log, ["pin:a", "unpin:a"]);
  });
}
