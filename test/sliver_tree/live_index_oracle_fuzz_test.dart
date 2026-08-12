/// All-registered-keys oracle fuzz for the live-index cache
/// (`plans/2026-08-11-item3-step2-live-index-cache.md`, test 2).
///
/// Randomized mutation script comparing `getIndexInParent` against an
/// INDEPENDENT public-API oracle (`liveRootKeys` / `getLiveChildren`
/// membership) for EVERY key ever created, after every operation. Pending
/// and purged keys are covered automatically: the live lists exclude
/// them, so the oracle's `indexOf` returns the same -1 the contract
/// demands, and a stale non-negative cached slot for such a key is
/// exactly the divergence this test exists to catch. Reads are
/// interleaved with mutations by construction (the oracle sweep runs
/// between every pair of operations), so refresh-then-mutate-then-read
/// sequences, the failure shape of a missing or misplaced generation
/// bump, are exercised constantly.
///
/// Runs with `TreeController.debugFullConsistencyChecks = true`, so every
/// read ALSO cross-checks the cache against the in-controller brute-force
/// scan; a divergence fails twice, once per oracle.
///
/// MUTATION VOCABULARY NOTE: this script calls every raw-sibling-list
/// mutator in the channel-1 inventory of the step 2 plan (setRoots,
/// insertRoot, insert, animated and immediate remove, moveNode,
/// reorderRoots, reorderChildren, setChildren, plus expand/collapse,
/// runBatch and animation-settling pumps for pending-deletion churn). A
/// FUTURE method that writes raw sibling lists is invisible to this fuzz
/// until it joins the script: add it here AND to the plan's channel-1
/// table when introducing one.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const int _iterations = 220;

void main() {
  testWidgets(
    "randomized mutations: getIndexInParent matches the public live-space "
    "oracle for every key ever created, after every operation",
    (tester) async {
      TreeController.debugFullConsistencyChecks = true;
      addTearDown(() {
        TreeController.debugFullConsistencyChecks = false;
      });

      final random = Random(20260811);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 80),
            curve: Curves.linear,
          ),
          enterExit: TreeAnimationSpec(
            duration: Duration(milliseconds: 80),
            curve: Curves.linear,
          ),
          reorderSlide: TreeAnimationSpec(
            duration: Duration(milliseconds: 80),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);

      int keyCounter = 0;
      String nextKey() {
        return "k${keyCounter++}";
      }

      final allKeysEver = <String>[];
      String trackKey(String key) {
        allKeysEver.add(key);
        return key;
      }

      controller.setRoots([
        for (int i = 0; i < 6; i++)
          TreeNode(key: trackKey(nextKey()), data: "seed"),
      ]);

      List<String> liveKeys() {
        final result = <String>[];
        void walk(List<String> keys) {
          for (final k in keys) {
            result.add(k);
            walk(controller.getLiveChildren(k));
          }
        }

        walk(controller.liveRootKeys);
        return result;
      }

      String? pickLive() {
        final live = liveKeys();
        if (live.isEmpty) return null;
        return live[random.nextInt(live.length)];
      }

      void verifyAll(int iteration, String op) {
        for (final key in allKeysEver) {
          final parent = controller.getParent(key);
          final list = parent == null
              ? controller.liveRootKeys
              : controller.getLiveChildren(parent);
          final expected = list.indexOf(key);
          final actual = controller.getIndexInParent(key);
          expect(
            actual,
            expected,
            reason:
                "iteration $iteration after $op: getIndexInParent($key) "
                "diverged from the live-list oracle",
          );
        }
      }

      int skipped = 0;
      int effectiveRootReorders = 0;
      int effectiveChildReorders = 0;

      // Shuffles a copy and guarantees a NON-IDENTITY permutation for
      // lists of length >= 2 (a small list shuffles to itself often, and
      // an identity reorder cannot expose a missing invalidation).
      List<String> shuffledDifferently(List<String> original) {
        final shuffled = List.of(original)..shuffle(random);
        if (original.length >= 2 &&
            List.generate(
              original.length,
              (i) => shuffled[i] == original[i],
            ).every((same) => same)) {
          final tmp = shuffled[0];
          shuffled[0] = shuffled[1];
          shuffled[1] = tmp;
        }
        return shuffled;
      }
      void guarded(void Function() op) {
        try {
          op();
        } on StateError {
          // Legitimate contract refusals (e.g. inserting under a
          // pending-deletion parent) are skipped, not failures.
          skipped++;
        } on ArgumentError {
          skipped++;
        }
      }

      void mutateOnce() {
        final op = random.nextInt(10);
        switch (op) {
          case 0:
            guarded(() {
              controller.insertRoot(
                TreeNode(key: trackKey(nextKey()), data: "r"),
                index: random.nextBool()
                    ? random.nextInt(controller.liveRootKeys.length + 1)
                    : null,
                animate: random.nextBool(),
              );
            });
          case 1:
            final parent = pickLive();
            if (parent == null) return;
            guarded(() {
              controller.insert(
                parentKey: parent,
                node: TreeNode(key: trackKey(nextKey()), data: "c"),
                index: random.nextBool()
                    ? random.nextInt(
                        controller.getLiveChildren(parent).length + 1,
                      )
                    : null,
                animate: random.nextBool(),
              );
            });
          case 2:
            final key = pickLive();
            if (key == null) return;
            guarded(() {
              controller.remove(key: key, animate: true);
            });
          case 3:
            final key = pickLive();
            if (key == null) return;
            guarded(() {
              controller.remove(key: key, animate: false);
            });
          case 4:
            final key = pickLive();
            if (key == null) return;
            final descendants = controller.getDescendants(key).toSet();
            final candidates = liveKeys()
                .where((k) => k != key && !descendants.contains(k))
                .toList();
            final String? newParent =
                candidates.isEmpty || random.nextBool()
                ? null
                : candidates[random.nextInt(candidates.length)];
            guarded(() {
              controller.moveNode(
                key,
                newParent,
                index: random.nextBool() ? 0 : null,
                animate: random.nextBool(),
              );
            });
          case 5:
            guarded(() {
              final roots = controller.liveRootKeys;
              if (roots.length < 2) return;
              controller.reorderRoots(
                shuffledDifferently(roots),
                animate: random.nextBool(),
              );
              effectiveRootReorders++;
            });
          case 6:
            // Bias toward parents that actually have reorderable lists:
            // an identity or single-element reorder cannot expose a
            // missing invalidation, which is exactly how a removed
            // reorderChildren bump slipped past this fuzz's first draft.
            final withChildren = liveKeys()
                .where((k) => controller.getLiveChildren(k).length >= 2)
                .toList();
            if (withChildren.isEmpty) return;
            final parent = withChildren[random.nextInt(withChildren.length)];
            guarded(() {
              controller.reorderChildren(
                parent,
                shuffledDifferently(controller.getLiveChildren(parent)),
                animate: random.nextBool(),
              );
              effectiveChildReorders++;
            });
          case 7:
            final parent = pickLive();
            if (parent == null) return;
            guarded(() {
              controller.setChildren(parent, [
                for (int i = 2 + random.nextInt(4); i > 0; i--)
                  TreeNode(key: trackKey(nextKey()), data: "s"),
              ]);
            });
          case 8:
            final key = pickLive();
            if (key == null) return;
            if (random.nextBool()) {
              controller.expand(key: key);
            } else {
              controller.collapse(key: key);
            }
          case 9:
            guarded(() {
              controller.runBatch(() {
                final parent = pickLive();
                if (parent != null) {
                  controller.insert(
                    parentKey: parent,
                    node: TreeNode(key: trackKey(nextKey()), data: "b"),
                    animate: false,
                  );
                }
                final victim = pickLive();
                if (victim != null) {
                  controller.remove(key: victim, animate: true);
                }
              });
            });
        }
      }

      for (int i = 0; i < _iterations; i++) {
        mutateOnce();
        verifyAll(i, "mutation");
        // Advance animations sometimes so pending-deletion exits complete
        // (purging nids, recycling them) and enter animations settle;
        // occasionally settle everything.
        if (i % 7 == 3) {
          await tester.pump(const Duration(milliseconds: 40));
          verifyAll(i, "pump");
        }
        if (i % 31 == 17) {
          await tester.pumpAndSettle();
          verifyAll(i, "settle");
        }
      }
      await tester.pumpAndSettle();
      verifyAll(_iterations, "final settle");

      // Sanity: the script must have genuinely exercised the tree, and
      // the guarded skips must not have swallowed the run.
      expect(
        allKeysEver.length,
        greaterThan(50),
        reason: "setup: the fuzz must create a meaningful number of keys",
      );
      expect(
        skipped,
        lessThan(_iterations ~/ 2),
        reason: "setup: contract-refusal skips must stay a minority",
      );
      // Coverage floors: the ops most likely to be silently neutered by
      // script drift (identity permutations, childless parents) must
      // have run in their EFFECTIVE form a meaningful number of times.
      expect(
        effectiveRootReorders,
        greaterThan(3),
        reason: "setup: non-identity root reorders must actually occur",
      );
      expect(
        effectiveChildReorders,
        greaterThan(3),
        reason: "setup: non-identity child reorders must actually occur",
      );
    },
  );
}
