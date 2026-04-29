/// Regression: moving a live node into a pending-deletion parent must be
/// rejected. Without the guard, the moved subtree gets orphaned when the
/// parent's exit animation finalizes — `_finalizeAnimation` only purges
/// descendants that are themselves pending-deletion, so a non-pending child
/// is left behind with a stale `parentKey` pointing at a freed nid, and the
/// grandparent's visible-subtree-size cache is decremented for a row that
/// still exists.
///
/// The fix mirrors the existing assertion on `insert(parentKey: ...)`:
/// pending-deletion parents are off-limits as targets for new children,
/// whether through `insert` or `moveNode`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("moveNode into a pending-deletion parent asserts in debug",
      (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 100),
    );
    addTearDown(controller.dispose);

    controller.setRoots([
      TreeNode(key: "A", data: "A"),
      TreeNode(key: "B", data: "B"),
    ]);
    controller.setChildren("A", [TreeNode(key: "x", data: "x")]);
    controller.expand(key: "A", animate: false);

    // Mark B as pending-deletion via animated remove.
    controller.remove(key: "B", animate: true);
    expect(controller.isPendingDeletion("B"), isTrue);

    // Attempt to move x under the pending-deletion B. Must reject — either
    // via assert (debug) or runtime exception (release). Without the guard,
    // x gets orphaned when B's exit animation finalizes.
    expect(
      () => controller.moveNode("x", "B"),
      throwsA(anyOf(isA<AssertionError>(), isA<StateError>())),
      reason: "moveNode must refuse a pending-deletion newParent — same "
          "policy as insert(parentKey:).",
    );

    // Drain B's exit animation so the standalone ticker stops before
    // teardown verifies all tickers were disposed.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  });
}
