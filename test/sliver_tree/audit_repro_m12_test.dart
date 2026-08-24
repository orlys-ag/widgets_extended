/// Repro for M12: `syncRoots` computes root insert indices in SURVIVOR
/// space while every root removal is still deferred to step 2', so the
/// not-yet-removed roots are still live at the write boundary
/// (`insertRoot(index:)` speaks live space) and the new root lands too far
/// up. Step 6's `reorderRoots` then repairs the order by appending the
/// now-pending root after the live ones, teleporting the exiting root to
/// the bottom instead of letting it exit in place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

TreeController<String, String> _controller(WidgetTester tester) {
  return TreeController<String, String>(
    vsync: tester,
    animationStyle: const TreeAnimationStyle(
      expandCollapse: TreeAnimationSpec(
        duration: Duration(milliseconds: 400),
        curve: Curves.linear,
      ),
    ),
  );
}

TreeNode<String, String> _n(String key) => TreeNode(key: key, data: key);

void main() {
  testWidgets(
    "a removed root exits in place: the new root lands after the surviving "
    "root, below the exiting one",
    (tester) async {
      final controller = _controller(tester);
      final sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      sync.syncRoots([_n("X"), _n("A")], animate: false);
      expect(controller.rootKeys, ["X", "A"], reason: "setup");

      sync.syncRoots([_n("A"), _n("N")], animate: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        controller.isPendingDeletion("X"),
        isTrue,
        reason: "setup: X must still be mid-exit",
      );
      expect(
        controller.rootKeys,
        ["X", "A", "N"],
        reason: "X must exit IN PLACE at the top with N entering below A; "
            "an insert index computed in survivor space lands N above the "
            "still-live X and step 6 then teleports X to the bottom",
      );

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "a genuinely deferred root (its subtree holds a mover) stays live at "
    "insert time and the new root's index is converted to live space",
    (tester) async {
      final controller = _controller(tester);
      final sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      sync.syncRoots(
        [_n("X"), _n("A")],
        childrenOf: (key) => key == "X" ? [_n("m")] : const [],
        animate: false,
      );
      expect(controller.rootKeys, ["X", "A"], reason: "setup");
      expect(controller.getParent("m"), "X", reason: "setup");

      sync.syncRoots(
        [_n("A"), _n("N")],
        childrenOf: (key) => key == "A" ? [_n("m")] : const [],
        animate: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        controller.getParent("m"),
        "A",
        reason: "setup: m must have moved under A during the sync",
      );
      expect(
        controller.isPendingDeletion("X"),
        isTrue,
        reason: "setup: X must still be mid-exit",
      );
      expect(
        controller.rootKeys,
        ["X", "A", "N"],
        reason: "X is deferred (its subtree held the mover m) and is still "
            "LIVE when N is inserted, so N's survivor-space index 1 must be "
            "converted to live-space index 2; without the conversion N "
            "lands at raw index 1 and step 6 teleports X to the bottom",
      );

      await tester.pumpAndSettle();
    },
  );
}
