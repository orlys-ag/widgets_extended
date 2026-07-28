/// Unit tests for [TreeController.hasLiveChildren] (D10): the
/// non-allocating variant of `getLiveChildren(key).isNotEmpty` used by the
/// drop-zone resolver's per-pointer-move hot path. Pinned agreement
/// property: the two must answer identically in every state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets("false for unknown keys and childless nodes", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);
    controller.setRoots([const TreeNode(key: "leaf", data: "L")]);

    expect(controller.hasLiveChildren("missing"), isFalse);
    expect(controller.hasLiveChildren("leaf"), isFalse);
    expect(controller.getLiveChildren("leaf").isNotEmpty, isFalse,
        reason: "agreement with the allocating form");
    expect(controller.liveChildCount("missing"), 0);
    expect(controller.liveChildCount("leaf"), 0);
    expect(controller.liveRootCount, controller.liveRootKeys.length,
        reason: "count agreement with the allocating form");
  });

  testWidgets("true with live children, false once all are mid-exit",
      (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 300),
      animationCurve: Curves.linear,
    );
    addTearDown(controller.dispose);
    controller.setRoots([const TreeNode(key: "p", data: "P")]);
    controller.setChildren("p", [
      const TreeNode(key: "c1", data: "C1"),
      const TreeNode(key: "c2", data: "C2"),
    ]);
    controller.expand(key: "p", animate: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverTree<String, String>(
                controller: controller,
                nodeBuilder: (context, key, depth) {
                  return SizedBox(height: 50, child: Text(key));
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.hasLiveChildren("p"), isTrue);

    // Remove c1 — mixed live/pending state must still report true.
    controller.remove(key: "c1");
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.isPendingDeletion("c1"), isTrue,
        reason: "setup: c1 must be mid-exit");
    expect(controller.hasLiveChildren("p"), isTrue,
        reason: "c2 is still live");
    expect(controller.getLiveChildren("p").isNotEmpty, isTrue,
        reason: "agreement with the allocating form");
    expect(controller.liveChildCount("p"), 1,
        reason: "mixed live/pending: only c2 counts");
    expect(controller.liveChildCount("p"),
        controller.getLiveChildren("p").length,
        reason: "count agreement with the allocating form");

    // Remove c2 too — all children pending-deletion: the FULL list is
    // non-empty but there are no LIVE children.
    controller.remove(key: "c2");
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.getChildren("p").isNotEmpty, isTrue,
        reason: "setup: the full list still holds the mid-exit children");
    expect(controller.hasLiveChildren("p"), isFalse,
        reason: "every child is pending-deletion");
    expect(controller.getLiveChildren("p").isNotEmpty, isFalse,
        reason: "agreement with the allocating form");

    // After the exits settle and the children purge, still false.
    await tester.pumpAndSettle();
    expect(controller.hasLiveChildren("p"), isFalse);
  });
}
