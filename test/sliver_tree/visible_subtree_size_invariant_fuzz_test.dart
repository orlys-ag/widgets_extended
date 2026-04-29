/// Randomized fuzz test that asserts the visible-subtree-size cache
/// invariant holds after every mutation. Drives a large mix of insert /
/// remove / expand / collapse / reparent / setChildren / expandAll /
/// collapseAll operations against a random valid live key, then calls
/// the controller's debug invariant check.
///
/// Bug class targeted: cache desync where `_visibleSubtreeSizeByNid`
/// drifts away from the structural definition (own + sum(children)).
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("visible-subtree-size invariant holds under random churn", (
    tester,
  ) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    final rng = Random(0xDEADBEEF);
    var nextKeyCounter = 0;
    String mintKey() => "k${nextKeyCounter++}";

    // Seed: 5 roots, each with 3 children, all collapsed.
    final seedRoots = <TreeNode<String, String>>[];
    for (var r = 0; r < 5; r++) {
      seedRoots.add(TreeNode(key: mintKey(), data: "root"));
    }
    controller.setRoots(seedRoots);
    for (final root in seedRoots) {
      controller.setChildren(root.key, [
        for (var c = 0; c < 3; c++)
          TreeNode(key: mintKey(), data: "child"),
      ]);
    }

    String? pickRandomLiveKey() {
      final keys = controller.debugAllKeys.toList(growable: false);
      if (keys.isEmpty) return null;
      return keys[rng.nextInt(keys.length)];
    }

    for (var op = 0; op < 4000; op++) {
      final action = rng.nextInt(8);
      try {
        switch (action) {
          case 0:
            // Insert a fresh child under a random live parent.
            final parent = pickRandomLiveKey();
            if (parent == null) break;
            controller.insert(
              parentKey: parent,
              node: TreeNode(key: mintKey(), data: "ins"),
              animate: false,
            );
            break;

          case 1:
            // Remove a random live key (skip if it's one of the
            // root-set keys to keep the seed alive).
            final key = pickRandomLiveKey();
            if (key == null) break;
            final roots = controller.liveRootKeys;
            if (roots.contains(key) && roots.length <= 1) {
              break; // keep at least one root alive
            }
            controller.remove(key: key, animate: false);
            break;

          case 2:
            // Expand a random live key.
            final key = pickRandomLiveKey();
            if (key == null) break;
            controller.expand(key: key, animate: false);
            break;

          case 3:
            // Collapse a random live key.
            final key = pickRandomLiveKey();
            if (key == null) break;
            controller.collapse(key: key, animate: false);
            break;

          case 4:
            // Reparent a random live key under a random other live key.
            final keys = controller.debugAllKeys.toList(growable: false);
            if (keys.length < 2) break;
            final src = keys[rng.nextInt(keys.length)];
            final dst = keys[rng.nextInt(keys.length)];
            if (src == dst) break;
            // Skip if dst is in src's subtree (would cycle and throw).
            // moveNode itself checks via _getDescendants — we mirror
            // the check by attempting and swallowing the StateError.
            try {
              controller.moveNode(src, dst);
            } on StateError {
              // Cycle attempt — fine, just skip this iteration.
            }
            break;

          case 5:
            // setChildren on a random live key with a fresh child set.
            final parent = pickRandomLiveKey();
            if (parent == null) break;
            final newChildCount = rng.nextInt(4); // 0..3
            controller.setChildren(parent, [
              for (var c = 0; c < newChildCount; c++)
                TreeNode(key: mintKey(), data: "sc"),
            ]);
            break;

          case 6:
            // expandAll
            controller.expandAll(animate: false);
            break;

          case 7:
            // collapseAll
            controller.collapseAll(animate: false);
            break;
        }
      } on AssertionError {
        // Some mutations may target keys that became invalid mid-loop
        // (e.g. removed already). Public API asserts; tolerate and
        // continue — the invariant check below still runs every iter.
      }

      await tester.pump();
      controller.debugAssertVisibleSubtreeSizeConsistency();
    }
  });
}
