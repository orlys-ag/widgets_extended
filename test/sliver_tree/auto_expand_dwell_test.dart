/// D7 repro tests: hovering `into` a collapsed parent for the dwell
/// duration auto-expands it, so the user can see (and target) the
/// revealed children before committing. Headless against a scripted fake
/// port — the dwell is a controller concern, no tree layout needed.
///
/// Repro-test methodology: the expansion expectations fail on pre-D7 code
/// (no dwell timer exists).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/reorder_render_port.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/tree_reorder_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

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

  // Static script: p(0..50), x(50..100) — enough for hover targeting; the
  // dwell logic never needs post-expand geometry.
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
    Map<String, double>? baselineYOverrides,
  }) {}
}

Future<ScrollableState> _mountScrollable(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
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

TreeController<String, String> _collapsedParentTree(WidgetTester tester) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationDuration: Duration.zero,
  );
  controller.setRoots([
    const TreeNode(key: "p", data: "P"),
    const TreeNode(key: "x", data: "X"),
  ]);
  controller.setChildren("p", [const TreeNode(key: "c1", data: "C1")]);
  // p stays collapsed — the dwell's job is to open it.
  return controller;
}

void main() {
  testWidgets("hovering into a collapsed parent past the dwell expands it",
      (tester) async {
    final controller = _collapsedParentTree(tester);
    addTearDown(controller.dispose);
    final port = _FakePort(controller: controller);
    final reorder = TreeReorderController<String>(
      treeController: controller,
      vsync: tester,
    );
    addTearDown(reorder.dispose);
    final scrollable = await _mountScrollable(tester);

    // Drag x, pointer at the middle of p (y=25 → into-p).
    reorder.startDrag(
      key: "x",
      renderPort: port,
      scrollable: scrollable,
      pointerGlobal: const Offset(200, 25),
    );
    expect(reorder.currentTarget?.zone, TreeDropZone.into,
        reason: "setup: middle of p resolves the into zone");
    expect(controller.isExpanded("p"), isFalse,
        reason: "setup: p starts collapsed");

    // Hold past the default 700ms dwell.
    await tester.pump(const Duration(milliseconds: 800));

    expect(controller.isExpanded("p"), isTrue,
        reason: "dwelling on an into-target must auto-expand it so the "
            "user can see and target the revealed children");
    expect(reorder.isDragging, isTrue,
        reason: "auto-expand must not disturb the session");

    reorder.cancelDrag();
  });

  testWidgets("moving off the target before the dwell cancels the expand",
      (tester) async {
    final controller = _collapsedParentTree(tester);
    addTearDown(controller.dispose);
    final port = _FakePort(controller: controller);
    final reorder = TreeReorderController<String>(
      treeController: controller,
      vsync: tester,
    );
    addTearDown(reorder.dispose);
    final scrollable = await _mountScrollable(tester);

    reorder.startDrag(
      key: "x",
      renderPort: port,
      scrollable: scrollable,
      pointerGlobal: const Offset(200, 25),
    );
    expect(reorder.currentTarget?.zone, TreeDropZone.into,
        reason: "setup: dwell armed on into-p");

    // Leave before the dwell fires (pointer onto row x — no into target).
    await tester.pump(const Duration(milliseconds: 300));
    reorder.updateDrag(const Offset(200, 75));
    await tester.pump(const Duration(milliseconds: 800));

    expect(controller.isExpanded("p"), isFalse,
        reason: "a dwell abandoned before the delay must not expand");

    reorder.cancelDrag();
  });

  testWidgets("session end before the dwell cancels the expand",
      (tester) async {
    final controller = _collapsedParentTree(tester);
    addTearDown(controller.dispose);
    final port = _FakePort(controller: controller);
    final reorder = TreeReorderController<String>(
      treeController: controller,
      vsync: tester,
    );
    addTearDown(reorder.dispose);
    final scrollable = await _mountScrollable(tester);

    reorder.startDrag(
      key: "x",
      renderPort: port,
      scrollable: scrollable,
      pointerGlobal: const Offset(200, 25),
    );
    await tester.pump(const Duration(milliseconds: 300));
    reorder.cancelDrag();
    await tester.pump(const Duration(milliseconds: 800));

    expect(controller.isExpanded("p"), isFalse,
        reason: "a cancelled session must never fire its pending dwell");
  });

  testWidgets("autoExpandDelay: null disables the dwell entirely",
      (tester) async {
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

    reorder.startDrag(
      key: "x",
      renderPort: port,
      scrollable: scrollable,
      pointerGlobal: const Offset(200, 25),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(controller.isExpanded("p"), isFalse,
        reason: "null delay opts out of auto-expand");

    reorder.cancelDrag();
  });

  testWidgets("a childless collapsed target never arms the dwell",
      (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      const TreeNode(key: "p", data: "P"),
      const TreeNode(key: "x", data: "X"),
    ]);
    // p has NO children: expanding it would reveal nothing.
    final port = _FakePort(controller: controller);
    final reorder = TreeReorderController<String>(
      treeController: controller,
      vsync: tester,
    );
    addTearDown(reorder.dispose);
    final scrollable = await _mountScrollable(tester);

    reorder.startDrag(
      key: "x",
      renderPort: port,
      scrollable: scrollable,
      pointerGlobal: const Offset(200, 25),
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(controller.isExpanded("p"), isFalse,
        reason: "expanding a live-childless node reveals nothing — the "
            "dwell must not arm");

    reorder.cancelDrag();
  });
}
