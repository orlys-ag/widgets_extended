/// Unit tests for the live-index cache component (stamp algebra) plus the
/// adversarial-comparator pin from the step 2 plan
/// (`plans/2026-08-11-item3-step2-live-index-cache.md`, tests 5 and 6).
///
/// The comparator pin is the load-bearing one: user comparators run INSIDE
/// mutation windows (`_sortedIndex` executes after the relocate unlink in
/// `insertRoot`/`insert`/`moveNode`), and nothing forbids a comparator
/// from calling `getIndexInParent`. The cache's exit-placed generation
/// bump is what makes such reads self-healing: their refreshes are
/// discarded by the mutator's own bump, so they can never poison
/// post-mutation reads. This is the test that stops a future refactor
/// from quietly moving the bump to method entry, which would turn a
/// comparator read into a trusted refresh of a half-mutated list.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/_live_index_cache.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  group("LiveIndexCache stamp algebra", () {
    test("fresh slots and stamps are stale by construction", () {
      final cache = LiveIndexCache();
      cache.resizeForCapacity(8);
      expect(cache.generation, 1, reason: "generation starts at 1");
      expect(
        cache.isParentFresh(0),
        isFalse,
        reason: "zero-filled parent stamp must be stale against gen 1",
      );
      expect(
        cache.isParentFresh(kRootListParentNid),
        isFalse,
        reason: "the roots scalar starts at 0, stale against gen 1",
      );
      expect(cache.readSlot(0), -1, reason: "unwritten slot reads -1");
    });

    test("refresh round trip, then a bump invalidates everything", () {
      final cache = LiveIndexCache();
      cache.resizeForCapacity(8);
      cache.beginRefresh(0);
      cache.writeSlot(1, 0);
      cache.writeSlot(2, 1);
      expect(cache.isParentFresh(0), isTrue);
      expect(cache.readSlot(1), 0);
      expect(cache.readSlot(2), 1);
      expect(
        cache.readSlot(3),
        -1,
        reason: "a nid the refresh did not write is not a member",
      );

      cache.bump();
      expect(cache.isParentFresh(0), isFalse);
      expect(
        cache.readSlot(1),
        -1,
        reason: "slot stamps from a prior generation must read -1",
      );
    });

    test("roots and parent stamps are independent", () {
      final cache = LiveIndexCache();
      cache.resizeForCapacity(8);
      cache.beginRefresh(kRootListParentNid);
      cache.writeSlot(0, 0);
      expect(cache.isParentFresh(kRootListParentNid), isTrue);
      expect(
        cache.isParentFresh(0),
        isFalse,
        reason: "refreshing roots must not freshen nid 0's child list",
      );
    });

    test("resizeForCapacity preserves live slots and zero-fills growth", () {
      final cache = LiveIndexCache();
      cache.resizeForCapacity(4);
      cache.beginRefresh(0);
      cache.writeSlot(1, 5);
      cache.resizeForCapacity(64);
      expect(cache.readSlot(1), 5, reason: "grown copy preserves slots");
      expect(cache.isParentFresh(0), isTrue);
      expect(
        cache.readSlot(63),
        -1,
        reason: "grown tail is zero-filled, stale against gen >= 1",
      );
    });

    test("reset drops arrays without rewinding the generation", () {
      final cache = LiveIndexCache();
      cache.resizeForCapacity(8);
      cache.beginRefresh(kRootListParentNid);
      cache.beginRefresh(0);
      cache.writeSlot(1, 3);
      final genBeforeReset = cache.generation;

      cache.reset();
      expect(
        cache.generation,
        genBeforeReset,
        reason: "reset never rewinds the generation (the invariant that "
            "makes stale slots unforgeable)",
      );
      expect(cache.isParentFresh(kRootListParentNid), isFalse);
      expect(cache.readSlot(1), -1, reason: "dropped arrays read -1");

      cache.resizeForCapacity(8);
      expect(
        cache.isParentFresh(0),
        isFalse,
        reason: "regrown zero-filled stamps are stale against gen >= 1",
      );
      expect(cache.readSlot(1), -1);
    });
  });

  group("adversarial comparator (mid-mutation reads)", () {
    testWidgets(
      "comparator reads inside the mutation window cannot poison "
      "post-mutation reads",
      (tester) async {
        late final TreeController<String, String> controller;
        int midMutationReads = 0;
        final observedMidMutation = <int>{};
        controller = TreeController<String, String>(
          vsync: tester,
          animationStyle: TreeAnimationStyle.disabled,
          comparator: (a, b) {
            // Adversarial: read a live index during the sort. The sorted
            // insert position is computed AFTER the relocate unlink, so
            // this runs against a half-mutated list (the moved key is
            // unlinked, not yet re-inserted).
            observedMidMutation.add(controller.getIndexInParent(a.key));
            observedMidMutation.add(controller.getIndexInParent(b.key));
            midMutationReads += 2;
            return a.data.compareTo(b.data);
          },
        );
        addTearDown(controller.dispose);
        controller.setRoots([
          for (int i = 0; i < 8; i++)
            TreeNode(key: "r$i", data: i.toString().padLeft(2, "0")),
        ]);

        // Warm the cache so the comparator's mid-window reads exercise
        // real refreshes, not first-touch misses only.
        for (int i = 0; i < 8; i++) {
          expect(controller.getIndexInParent("r$i"), i);
        }

        // moveNode with a comparator and no index takes the sorted-insert
        // path: unlink r3 from the roots, THEN run the comparator to find
        // the sorted slot, then re-insert. The comparator observes the
        // half-mutated list; r3's own reads there must be -1 (slot-stamp
        // miss), never a stale pre-unlink index presented as current.
        controller.moveNode("r3", null, animate: false);

        expect(
          midMutationReads,
          greaterThan(0),
          reason: "setup: the comparator must actually have run",
        );
        expect(
          observedMidMutation,
          contains(-1),
          reason:
              "setup: every comparison involves the node being placed, so "
              "the comparator must have observed the moved key as unlinked "
              "(-1 via the slot-stamp miss); if this fails, the test is "
              "not exercising the half-mutated window at all",
        );

        // The payoff: post-mutation reads agree with the public
        // live-space oracle for every root. A refresh captured mid-window
        // that survived the mutation would diverge here.
        final oracle = controller.liveRootKeys;
        for (int i = 0; i < 8; i++) {
          expect(
            controller.getIndexInParent("r$i"),
            oracle.indexOf("r$i"),
            reason: "post-mutation index for r$i must match the live list",
          );
        }
        // Sorted by data, so the order is unchanged: r3 lands back at 3.
        expect(controller.getIndexInParent("r3"), 3);
      },
    );
  });
}
