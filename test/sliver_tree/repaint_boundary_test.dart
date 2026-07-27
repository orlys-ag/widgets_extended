/// Regression test for audit item 5.10: [SliverTree.addRepaintBoundaries]
/// wraps each row in a [RepaintBoundary] by default (matching
/// ListView/SliverList convention), so scroll/slide frames re-composite
/// cached row layers instead of re-recording every visible row's display
/// list. Opting out removes the wrappers.
///
/// R6 (2026-07-15 review): the default-on oracle must scope its search to
/// INSIDE the sliver. A MaterialApp route always contains
/// framework-inserted [RepaintBoundary]s above the sliver (every page is
/// wrapped by `_ModalScope`), so "the row has SOME RepaintBoundary
/// ancestor" is tautologically true and proves nothing about
/// [SliverTree.addRepaintBoundaries]. Both tests share one helper and
/// assert exact mirror outcomes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Widget _harness(
  TreeController<String, String> controller, {
  bool? addRepaintBoundaries,
}) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverTree<String, String>(
            controller: controller,
            addRepaintBoundaries: addRepaintBoundaries ?? true,
            nodeBuilder: (context, key, depth) {
              return SizedBox(
                key: ValueKey("row-$key"),
                height: 48,
                child: Text(key),
              );
            },
          ),
        ],
      ),
    ),
  );
}

/// Whether the NEAREST [RepaintBoundary] ancestor of the row for [rowKey]
/// lives INSIDE the [SliverTree] element — i.e. it is the per-row wrapper
/// inserted by `addRepaintBoundaries`, not a framework boundary above the
/// sliver (route/viewport).
bool _hasRowBoundaryInsideSliver(WidgetTester tester, Key rowKey) {
  final boundaries = find.ancestor(
    of: find.byKey(rowKey),
    matching: find.byType(RepaintBoundary),
  );
  if (boundaries.evaluate().isEmpty) {
    return false;
  }
  // find.ancestor walks upward, so `first` is the nearest boundary.
  final boundary = tester.element(boundaries.first);
  final sliver = tester.element(find.byType(SliverTree<String, String>));
  bool insideSliver = false;
  boundary.visitAncestorElements((ancestor) {
    if (identical(ancestor, sliver)) {
      insideSliver = true;
      return false;
    }
    return true;
  });
  return insideSliver;
}

void main() {
  testWidgets("rows are wrapped in RepaintBoundary by default",
      (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      const TreeNode(key: "a", data: "A"),
      const TreeNode(key: "b", data: "B"),
    ]);

    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    expect(
      _hasRowBoundaryInsideSliver(tester, const ValueKey("row-a")),
      isTrue,
      reason: "each row must be wrapped in a RepaintBoundary INSIDE the "
          "sliver by default — a boundary above the sliver is the "
          "route/viewport's own and proves nothing (R6)",
    );
    expect(
      _hasRowBoundaryInsideSliver(tester, const ValueKey("row-b")),
      isTrue,
      reason: "every row gets its own wrapper, not just the first",
    );
  });

  testWidgets("addRepaintBoundaries: false leaves rows unwrapped",
      (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);
    controller.setRoots([const TreeNode(key: "a", data: "A")]);

    await tester.pumpWidget(
      _harness(controller, addRepaintBoundaries: false),
    );
    await tester.pumpAndSettle();

    expect(
      _hasRowBoundaryInsideSliver(tester, const ValueKey("row-a")),
      isFalse,
      reason: "with addRepaintBoundaries: false no per-row boundary may "
          "be inserted inside the sliver (the nearest boundary ancestor "
          "must be the viewport's own, outside the sliver)",
    );
  });
}
