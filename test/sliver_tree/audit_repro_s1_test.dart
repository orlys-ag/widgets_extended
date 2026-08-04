/// Audit repro for finding S1 (2026-07-15 audit): orphaned mid-exit
/// descendants keep a dangling `_parentByNid` pointer to their purged
/// parent's freed nid; when that nid is recycled by a new insert before the
/// descendant finalizes, the descendant's finalize decrements the RECYCLED
/// node's visible-subtree-size chain (ABA), globally desyncing the cache.
///
/// Sequence:
///   1. insertRoot(P, animate: true) → P mid-enter at partial extent.
///   2. setChildren(P, [D]); expand(P, animate: false) → D visible at full.
///   3. remove(P, animate: true): P exits from ~partial extent with
///      speedMultiplier > 1, D exits from full extent at multiplier 1 →
///      P finalizes first, purging P (freeing its nid) while D survives
///      mid-exit with _parentByNid[D] == freed P-nid.
///   4. insertRoot(K) → K recycles P's freed nid (LIFO free list).
///   5. D finalizes → _parentKeyOfKey(D) resolves K (not null!) →
///      bumpFromSelf(K's nid, -1) corrupts K's subtree-size slot.
///
/// EXPECTED (correct) behavior asserted here: after everything settles the
/// visible-subtree-size cache is consistent (the debug validator passes)
/// and K is still visible. On buggy code the validator throws
/// (subtree size of K == 0 while K is visible) or the bumpFromSelf
/// negative-value assert fires earlier.
library;

import 'package:widgets_extended/sliver_tree/animation_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree_widget.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

Widget _harness(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverTree<String, String>(
            controller: controller,
            nodeBuilder: (context, key, depth) {
              return SizedBox(
                key: ValueKey(key),
                height: 100,
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
  testWidgets(
    "descendant finalizing after its purged parent's nid was recycled "
    "must not corrupt the recycled node's subtree-size cache",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 300), curve: Curves.linear)),
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "z", data: "Z")]);
      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      // 1. P enters animated; let it reach ~30% extent.
      controller.insertRoot(const TreeNode(key: "p", data: "P"), index: 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      // 2. Give P a full-extent child D.
      controller.setChildren("p", [const TreeNode(key: "d", data: "D")]);
      controller.expand(key: "p", animate: false);
      await tester.pump();

      // 3. Remove P: P exits from partial extent (fast multiplier), D from
      //    full extent (multiplier 1) → P finalizes well before D.
      controller.remove(key: "p");
      await tester.pump();

      // Advance until P is purged but D is still mid-exit.
      bool pPurgedBeforeD = false;
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        final pGone = controller.getNodeData("p") == null;
        final dAlive = controller.getNodeData("d") != null;
        if (pGone && dAlive) {
          pPurgedBeforeD = true;
          break;
        }
        if (pGone && !dAlive) break;
      }
      expect(pPurgedBeforeD, isTrue,
          reason: "setup: P must finalize (purge) while D is still mid-exit "
              "for the dangling-parent-nid window to open");

      // 4. Recycle P's freed nid with an unrelated root K.
      controller.insertRoot(
        const TreeNode(key: "k", data: "K"),
        index: 0,
        animate: false,
      );
      await tester.pump();

      // 5. Let D finalize; then check cache consistency.
      await tester.pumpAndSettle();

      expect(controller.getNodeData("d"), isNull,
          reason: "D should be purged after its exit settles");
      expect(controller.visibleNodes.contains("k"), isTrue);

      // The critical oracle: the visible-subtree-size cache must still be
      // consistent. On buggy code K's slot was decremented for D's exit.
      controller.debugAssertVisibleSubtreeSizeConsistency();
    },
  );
}
