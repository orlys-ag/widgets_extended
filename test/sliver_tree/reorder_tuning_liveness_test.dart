/// Repro tests for live drag tunings: `autoExpandDelay`,
/// `autoScrollEdgeZone` and `autoScrollMaxVelocity` are mutable on
/// [TreeReorderController] and captured once per drag session at
/// `startDrag`, the same per-session policy as the animation style. A
/// change between drags applies to the next session; a mid-drag change
/// never retunes the live one. `SyncedSliverTree` pushes the config's
/// tunings onto the controller on every rebuild.
///
/// Repro-test methodology: on pre-fix code the controller fields were
/// final and the widgets forwarded them only at construction, so the
/// widget-level expectations here fail (the controller keeps its
/// construction-time values) and the controller-level mutations do not
/// compile at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Scripted two-row render port, the same fake as
/// `auto_expand_dwell_test.dart`: p(0..50), x(50..100).
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
  ({String key, double paintedOffset, double extent})? findPinnedRowAtPaintedY(
    double scrollY,
  ) {
    return null;
  }

  @override
  ({double paintedOffset, double extent})? paintedRowBounds(String key) {
    return switch (key) {
      "p" => (paintedOffset: 0.0, extent: 50.0),
      "x" => (paintedOffset: 50.0, extent: 50.0),
      _ => null,
    };
  }

  @override
  ({String key, double paintedOffset, double extent})? findRowAtPaintedY(
    double scrollY,
  ) {
    if (scrollY < 50) {
      return (key: "p", paintedOffset: 0.0, extent: 50.0);
    }
    return (key: "x", paintedOffset: 50.0, extent: 50.0);
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

Future<ScrollableState> _mountScrollable(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [SliverToBoxAdapter(child: SizedBox(height: 2000))],
        ),
      ),
    ),
  );
  return tester.state<ScrollableState>(find.byType(Scrollable));
}

TreeController<String, String> _collapsedParentTree(WidgetTester tester) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  controller.setRoots([
    const TreeNode(key: "p", data: "P"),
    const TreeNode(key: "x", data: "X"),
  ]);
  controller.setChildren("p", [const TreeNode(key: "c1", data: "C1")]);
  // p stays collapsed; the dwell's job is to open it.
  return controller;
}

/// Starts dragging x with the pointer in the middle of p (the into
/// zone), asserting the setup so the dwell expectations are meaningful.
void _startDragOverP(
  TreeReorderController<String> reorder,
  _FakePort port,
  ScrollableState scrollable,
  TreeController<String, String> controller,
) {
  reorder.startDrag(
    key: "x",
    renderPort: port,
    scrollable: scrollable,
    pointerGlobal: const Offset(200, 25),
  );
  expect(
    reorder.currentTarget?.zone,
    TreeDropZone.into,
    reason: "setup: middle of p resolves the into zone",
  );
  expect(
    controller.isExpanded("p"),
    isFalse,
    reason: "setup: p starts collapsed",
  );
}

void main() {
  testWidgets("a tuning set between drags applies to the next session", (
    tester,
  ) async {
    final controller = _collapsedParentTree(tester);
    addTearDown(controller.dispose);
    final port = _FakePort(controller: controller);
    final reorder = TreeReorderController<String>(
      treeController: controller,
      vsync: tester,
      autoExpandDelay: null,
    );
    addTearDown(reorder.dispose);
    final scrollable = await _mountScrollable(tester);

    _startDragOverP(reorder, port, scrollable, controller);
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      controller.isExpanded("p"),
      isFalse,
      reason: "setup: the first session captured the null delay",
    );
    reorder.cancelDrag();

    reorder.autoExpandDelay = const Duration(milliseconds: 250);
    _startDragOverP(reorder, port, scrollable, controller);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      controller.isExpanded("p"),
      isTrue,
      reason: "the next session must capture the delay set between drags",
    );
    reorder.cancelDrag();
  });

  testWidgets("a mid-drag tuning change never retunes the live session", (
    tester,
  ) async {
    final controller = _collapsedParentTree(tester);
    addTearDown(controller.dispose);
    final port = _FakePort(controller: controller);
    final reorder = TreeReorderController<String>(
      treeController: controller,
      vsync: tester,
      autoExpandDelay: null,
    );
    addTearDown(reorder.dispose);
    final scrollable = await _mountScrollable(tester);

    _startDragOverP(reorder, port, scrollable, controller);
    // Mid-drag change: the live session must keep its captured null.
    reorder.autoExpandDelay = const Duration(milliseconds: 100);
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      controller.isExpanded("p"),
      isFalse,
      reason: "the live session keeps the tunings captured at startDrag",
    );
    reorder.cancelDrag();

    // The next session picks the new value up.
    _startDragOverP(reorder, port, scrollable, controller);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      controller.isExpanded("p"),
      isTrue,
      reason: "the next session must capture the mid-drag change",
    );
    reorder.cancelDrag();
  });

  testWidgets("SyncedSliverTree pushes changed drag tunings on rebuild", (
    tester,
  ) async {
    TreeReorderController<String>? captured;
    // ONE instance across pumps: the identity gate skips the re-diff, and
    // the tuning push must still run.
    final treeInput = [SyncedTreeNode<String, String>(key: "a", data: "A")];

    Widget harness(TreeReorderConfig<String> config) {
      return MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SyncedSliverTree<String, String>(
                tree: treeInput,
                itemBuilder: (context, node) {
                  return SizedBox(height: 40, child: Text(node.item));
                },
                reorder: config,
              ),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(
      harness(
        TreeReorderConfig<String>(
          onReorder: (key, newParent, index) {},
          onControllerCreated: (controller) {
            captured = controller;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      captured,
      isNotNull,
      reason: "setup: the reorder controller is handed out",
    );
    expect(
      captured!.autoExpandDelay,
      const Duration(milliseconds: 700),
      reason: "setup: construction seeds the config defaults",
    );
    expect(captured!.autoScrollEdgeZone, 48.0);
    expect(captured!.autoScrollMaxVelocity, 1200.0);

    await tester.pumpWidget(
      harness(
        TreeReorderConfig<String>(
          onReorder: (key, newParent, index) {},
          autoExpandDelay: const Duration(milliseconds: 150),
          autoScrollEdgeZone: 80.0,
          autoScrollMaxVelocity: 600.0,
        ),
      ),
    );
    expect(
      captured!.autoExpandDelay,
      const Duration(milliseconds: 150),
      reason: "a rebuild with new tunings must reach the controller",
    );
    expect(captured!.autoScrollEdgeZone, 80.0);
    expect(captured!.autoScrollMaxVelocity, 600.0);
  });
}
