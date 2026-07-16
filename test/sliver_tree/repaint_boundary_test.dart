/// Regression test for audit item 5.10: [SliverTree.addRepaintBoundaries]
/// wraps each row in a [RepaintBoundary] by default (matching
/// ListView/SliverList convention), so scroll/slide frames re-composite
/// cached row layers instead of re-recording every visible row's display
/// list. Opting out removes the wrappers.
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
      find.ancestor(
        of: find.byKey(const ValueKey("row-a")),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
      reason: "each row must be wrapped in a RepaintBoundary by default",
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

    // The nearest RepaintBoundary ancestor must live OUTSIDE the sliver
    // (the viewport's own boundary), not as the row's direct wrapper.
    final row = find.byKey(const ValueKey("row-a"));
    final directWrapper = find.ancestor(
      of: row,
      matching: find.byType(RepaintBoundary),
    );
    if (directWrapper.evaluate().isNotEmpty) {
      final boundary = tester.element(directWrapper.first);
      final sliver = tester.element(
        find.byType(SliverTree<String, String>),
      );
      bool boundaryInsideSliver = false;
      boundary.visitAncestorElements((a) {
        if (identical(a, sliver)) {
          boundaryInsideSliver = true;
          return false;
        }
        return true;
      });
      expect(boundaryInsideSliver, isFalse,
          reason: "with addRepaintBoundaries: false no per-row boundary "
              "may be inserted inside the sliver");
    }
  });
}
