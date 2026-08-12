/// Headless unit tests for [DropZoneResolver] — the D2 extraction.
///
/// Resolution is a pure function of controller state + hovered-row geometry
/// + pointer y, so the full zone table runs WITHOUT mounting a widget tree:
/// no SliverTree, no render object, no scrollable. `testWidgets` is used
/// only for the [TickerProvider] the TreeController constructor requires.
///
/// Row geometry convention used throughout: 50px rows, target row "top"
/// passed explicitly per call — mirroring what
/// `RenderSliverTree.findRowAtPaintedY` would report.
library;

import 'package:widgets_extended/sliver_tree/animation_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/_drop_zone_resolver.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

void main() {
  group("DropZoneResolver zone table", () {
    testWidgets("thirds over an accepting target: above / into / below", (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      final resolver = DropZoneResolver<String>(treeController: controller);

      // Hover row "a" (painted 0..50) while dragging "c".
      TreeDropTarget<String>? at(double pointerY) {
        return resolver.resolve(
          draggedKey: "c",
          targetKey: "a",
          targetPaintedY: 0.0,
          targetExtent: 50.0,
          pointerY: pointerY,
        );
      }

      final above = at(10.0);
      expect(above?.zone, TreeDropZone.above);
      expect(above?.parentKey, isNull);
      expect(above?.indexInFinalList, 0);
      expect(above?.depth, 0);

      final into = at(25.0);
      expect(into?.zone, TreeDropZone.into);
      expect(into?.parentKey, "a");
      expect(into?.indexInFinalList, 0);
      expect(into?.depth, 1);

      final below = at(45.0);
      expect(below?.zone, TreeDropZone.below);
      expect(below?.parentKey, isNull);
      expect(below?.indexInFinalList, 1);
    });

    testWidgets("row geometry passes through to the semantic target", (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);
      final resolver = DropZoneResolver<String>(treeController: controller);

      final target = resolver.resolve(
        draggedKey: "b",
        targetKey: "a",
        targetPaintedY: 730.0,
        targetExtent: 64.0,
        pointerY: 740.0,
      );
      expect(
        target?.targetPaintedY,
        730.0,
        reason:
            "presentation layers derive indicator geometry from the "
            "painted offsets the resolver was given",
      );
      expect(target?.targetExtent, 64.0);
    });

    testWidgets(
      "self-hover resolves the CURRENT-POSITION slot, never a dead zone",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationStyle: TreeAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);
        controller.setRoots([
          const TreeNode(key: "a", data: "A"),
          const TreeNode(key: "b", data: "B"),
          const TreeNode(key: "c", data: "C"),
        ]);
        final resolver = DropZoneResolver<String>(treeController: controller);

        // Self-hover collapses to a two-zone split (self can't accept
        // `into`), and both halves resolve to the current position. That is
        // a VALID target now — "drops back here" — so the indicator/gap
        // never goes dark while crossing your own row; the commit path
        // treats it as a settle-back, mutating nothing.
        for (final pointerY in [55.0, 65.0, 75.0, 85.0, 95.0]) {
          final target = resolver.resolve(
            draggedKey: "b",
            targetKey: "b",
            targetPaintedY: 50.0,
            targetExtent: 50.0,
            pointerY: pointerY,
          );
          expect(
            target,
            isNotNull,
            reason:
                "pointerY=$pointerY over the dragged row must resolve "
                "the current-position slot, not a dead zone",
          );
          expect(target?.parentKey, isNull);
          expect(
            target?.indexInFinalList,
            1,
            reason: "the slot IS b's current position",
          );
        }
      },
    );

    testWidgets("downward drag over the next sibling's top resolves the "
        "current-position slot (the classic downward dead zone)", (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      final resolver = DropZoneResolver<String>(treeController: controller);

      // Dragging "a" down onto the TOP THIRD of "b" (painted 50..100):
      // "above b" adjusts to a's own current index — previously nulled by
      // the no-op filter, leaving two-thirds of the next card dead on the
      // way down. Now it is the current-position slot.
      final target = resolver.resolve(
        draggedKey: "a",
        targetKey: "b",
        targetPaintedY: 50.0,
        targetExtent: 50.0,
        pointerY: 55.0,
      );
      expect(
        target,
        isNotNull,
        reason: "the top of the next sibling must never be a dead zone",
      );
      expect(target?.zone, TreeDropZone.above);
      expect(
        target?.indexInFinalList,
        0,
        reason:
            "the slot IS a's current position — honest 'returns "
            "here' feedback with natural crossing hysteresis",
      );
    });

    testWidgets("cycle: any zone parenting under the dragged subtree is null", (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [const TreeNode(key: "b", data: "B")]);
      controller.setChildren("b", [const TreeNode(key: "c", data: "C")]);
      controller.expand(key: "a", animate: false);
      controller.expand(key: "b", animate: false);
      final resolver = DropZoneResolver<String>(treeController: controller);

      // Dragging "a" over descendant "b" (painted 50..100). The safety
      // invariant: NO resolved target may ever parent inside a's subtree.
      // The upper half ("above b" → parent a) is a cycle → null; the
      // lower half's cycle candidates fall back through the D6 chain to
      // the ROOT current-position slot — honest "returns here" feedback
      // instead of a dead zone, still outside the dragged subtree.
      final upper = resolver.resolve(
        draggedKey: "a",
        targetKey: "b",
        targetPaintedY: 50.0,
        targetExtent: 50.0,
        pointerY: 55.0,
      );
      expect(
        upper,
        isNull,
        reason: "above-b parents under dragged a — a cycle",
      );

      for (final pointerY in [75.0, 95.0]) {
        final target = resolver.resolve(
          draggedKey: "a",
          targetKey: "b",
          targetPaintedY: 50.0,
          targetExtent: 50.0,
          pointerY: pointerY,
        );
        expect(
          target?.parentKey,
          isNull,
          reason:
              "pointerY=$pointerY: the only legal level is the "
              "root — never a parent inside a's own subtree",
        );
        expect(
          target?.indexInFinalList,
          0,
          reason: "pointerY=$pointerY resolves a's current position",
        );
      }
    });

    testWidgets(
      "below an expanded parent with live children resolves first-child",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationStyle: TreeAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);
        controller.setRoots([
          const TreeNode(key: "p", data: "P"),
          const TreeNode(key: "x", data: "X"),
        ]);
        controller.setChildren("p", [const TreeNode(key: "c1", data: "C1")]);
        controller.expand(key: "p", animate: false);
        final resolver = DropZoneResolver<String>(treeController: controller);

        final target = resolver.resolve(
          draggedKey: "x",
          targetKey: "p",
          targetPaintedY: 0.0,
          targetExtent: 50.0,
          pointerY: 45.0,
        );
        expect(target?.zone, TreeDropZone.below);
        expect(
          target?.parentKey,
          "p",
          reason:
              "the slot under an expanded parent's row is visually the "
              "first-child slot; commit must match",
        );
        expect(target?.indexInFinalList, 0);
        expect(target?.depth, 1);
      },
    );

    testWidgets("below an expanded parent whose only child is pending-deletion "
        "falls back to next-sibling semantics", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      // Three roots: with only [p, x], "below p" would be x's own current
      // slot and the no-op filter would null the target before the
      // branch under test is observable.
      controller.setRoots([
        const TreeNode(key: "p", data: "P"),
        const TreeNode(key: "q", data: "Q"),
        const TreeNode(key: "x", data: "X"),
      ]);
      controller.setChildren("p", [const TreeNode(key: "c1", data: "C1")]);
      controller.expand(key: "p", animate: false);

      // Make c1 pending-deletion mid-exit. hasLiveChildren("p") is now
      // false even though the FULL child list still contains c1 — the D10
      // query is what the resolver's first-child branch keys on.
      controller.remove(key: "c1");
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        controller.isPendingDeletion("c1"),
        isTrue,
        reason: "setup: c1 must be mid-exit",
      );
      expect(
        controller.hasLiveChildren("p"),
        isFalse,
        reason: "setup: p has no LIVE children",
      );

      final resolver = DropZoneResolver<String>(treeController: controller);
      final target = resolver.resolve(
        draggedKey: "x",
        targetKey: "p",
        targetPaintedY: 0.0,
        targetExtent: 50.0,
        pointerY: 45.0,
      );
      expect(target?.zone, TreeDropZone.below);
      expect(
        target?.parentKey,
        isNull,
        reason:
            "with no live children visible below p, the slot under "
            "its row is the next-sibling slot, not first-child",
      );

      // Let the exit finish so dispose is clean.
      await tester.pumpAndSettle();
    });

    testWidgets("below a collapsed parent keeps next-sibling semantics", (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      // Three roots — see the pending-deletion variant above for why two
      // would collapse into the no-op filter.
      controller.setRoots([
        const TreeNode(key: "p", data: "P"),
        const TreeNode(key: "q", data: "Q"),
        const TreeNode(key: "x", data: "X"),
      ]);
      controller.setChildren("p", [const TreeNode(key: "c1", data: "C1")]);
      // p stays collapsed.
      final resolver = DropZoneResolver<String>(treeController: controller);

      final target = resolver.resolve(
        draggedKey: "x",
        targetKey: "p",
        targetPaintedY: 0.0,
        targetExtent: 50.0,
        pointerY: 45.0,
      );
      expect(target?.zone, TreeDropZone.below);
      expect(target?.parentKey, isNull);
      expect(target?.indexInFinalList, 1);
    });

    testWidgets("same-parent index adjustment: dragged before the raw slot "
        "subtracts one", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      final resolver = DropZoneResolver<String>(treeController: controller);

      // Drag "a" below "c" (painted 100..150): raw slot 3, but removing
      // "a" (index 0) from the live list shifts it to 2 — the index in
      // the FINAL list.
      final target = resolver.resolve(
        draggedKey: "a",
        targetKey: "c",
        targetPaintedY: 100.0,
        targetExtent: 50.0,
        pointerY: 145.0,
      );
      expect(target?.zone, TreeDropZone.below);
      expect(target?.indexInFinalList, 2);
    });

    testWidgets("x-aware below zone (D6): preferredDepth selects the ancestor "
        "level at a subtree right-boundary", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      // X first so root-level drops below A's subtree are not no-ops.
      // A > B > C, all expanded: C is the last visible row of a 3-deep
      // right boundary — the classic ambiguous drop.
      controller.setRoots([
        const TreeNode(key: "x", data: "X"),
        const TreeNode(key: "a", data: "A"),
      ]);
      controller.setChildren("a", [const TreeNode(key: "b", data: "B")]);
      controller.setChildren("b", [const TreeNode(key: "c", data: "C")]);
      controller.expand(key: "a", animate: false);
      controller.expand(key: "b", animate: false);
      final resolver = DropZoneResolver<String>(treeController: controller);

      // Rows: x(0..50), a(50..100), b(100..150), c(150..200).
      TreeDropTarget<String>? at(int? preferredDepth) {
        return resolver.resolve(
          draggedKey: "x",
          targetKey: "c",
          targetPaintedY: 150.0,
          targetExtent: 50.0,
          pointerY: 195.0,
          preferredDepth: preferredDepth,
        );
      }

      // No hint → deepest candidate — exactly today's behavior.
      final noHint = at(null);
      expect(noHint?.zone, TreeDropZone.below);
      expect(noHint?.parentKey, "b");
      expect(noHint?.depth, 2);

      // Depth 1 → sibling of b, inside a.
      final depth1 = at(1);
      expect(depth1?.parentKey, "a");
      expect(depth1?.indexInFinalList, 1);
      expect(depth1?.depth, 1);

      // Depth 0 → root level, after a's whole subtree.
      final depth0 = at(0);
      expect(
        depth0?.parentKey,
        isNull,
        reason:
            "pointing at the root indent column below a 3-deep "
            "boundary must target the root level",
      );
      expect(
        depth0?.indexInFinalList,
        1,
        reason: "x (live index 0) removed and re-inserted after a",
      );
      expect(depth0?.depth, 0);

      // Out-of-range hints clamp to the candidate chain.
      expect(at(-3)?.parentKey, isNull, reason: "clamps up to depth 0");
      expect(at(99)?.parentKey, "b", reason: "clamps down to the deepest");
    });

    testWidgets(
      "x-aware below zone (D6): chain stops at the first non-boundary "
      "ancestor",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationStyle: TreeAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);
        controller.setRoots([
          const TreeNode(key: "x", data: "X"),
          const TreeNode(key: "a", data: "A"),
        ]);
        // b is NOT the last child of a (d follows), so the boundary below c
        // only spans depths {2, 1} — never the root level.
        controller.setChildren("a", [
          const TreeNode(key: "b", data: "B"),
          const TreeNode(key: "d", data: "D"),
        ]);
        controller.setChildren("b", [const TreeNode(key: "c", data: "C")]);
        controller.expand(key: "a", animate: false);
        controller.expand(key: "b", animate: false);
        final resolver = DropZoneResolver<String>(treeController: controller);

        // Rows: x(0..50), a(50..100), b(100..150), c(150..200), d(200..250).
        final target = resolver.resolve(
          draggedKey: "x",
          targetKey: "c",
          targetPaintedY: 150.0,
          targetExtent: 50.0,
          pointerY: 195.0,
          preferredDepth: 0,
        );
        expect(
          target?.parentKey,
          "a",
          reason:
              "depth 0 is not in the candidate chain (b has a later "
              "sibling), so the hint clamps to depth 1 — a slot between "
              "b's subtree and d",
        );
        expect(target?.indexInFinalList, 1);
      },
    );

    testWidgets(
      "x-aware below zone (D6): a filtered candidate falls back to the "
      "next-nearest depth",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationStyle: TreeAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);
        controller.setRoots([
          const TreeNode(key: "x", data: "X"),
          const TreeNode(key: "a", data: "A"),
        ]);
        controller.setChildren("a", [const TreeNode(key: "b", data: "B")]);
        controller.setChildren("b", [const TreeNode(key: "c", data: "C")]);
        controller.expand(key: "a", animate: false);
        controller.expand(key: "b", animate: false);
        final resolver = DropZoneResolver<String>(
          treeController: controller,
          // Root-level drops are vetoed by policy.
          canAcceptDrop: ({required movingKey, newParent, index}) {
            return newParent != null;
          },
        );

        final target = resolver.resolve(
          draggedKey: "x",
          targetKey: "c",
          targetPaintedY: 150.0,
          targetExtent: 50.0,
          pointerY: 195.0,
          preferredDepth: 0,
        );
        expect(
          target?.parentKey,
          "a",
          reason:
              "the vetoed depth-0 candidate must fall back to the "
              "nearest surviving level (depth 1), not null the whole "
              "resolution",
        );
      },
    );

    testWidgets(
      "above a row at a LEFT boundary chains to the previous subtree's "
      "tail when the shallow slot is filtered (section-crossing dead "
      "band)",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationStyle: TreeAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);
        // Two "sections" with children — the workspaces shape. The slot
        // above secB is the SAME visible slot as secA's tail.
        controller.setRoots([
          const TreeNode(key: "secA", data: "A"),
          const TreeNode(key: "secB", data: "B"),
        ]);
        controller.setChildren("secA", [
          const TreeNode(key: "a1", data: "A1"),
          const TreeNode(key: "a2", data: "A2"),
        ]);
        controller.setChildren("secB", [const TreeNode(key: "b1", data: "B1")]);
        controller.expand(key: "secA", animate: false);
        controller.expand(key: "secB", animate: false);

        // Sectioned policy: items may only live under sections.
        final resolver = DropZoneResolver<String>(
          treeController: controller,
          canAcceptDrop: ({required movingKey, newParent, index}) {
            return newParent == "secA" || newParent == "secB";
          },
        );

        // Rows: secA(0..50), a1(50..100), a2(100..150), secB(150..200).
        // Dragging a1, pointer in secB's top third → above-secB. The
        // shallow slot (root level) is vetoed; pre-fix this was NULL — the
        // oscillating dead band above every section header. The chain must
        // fall back to secA's tail: the deeper expression of the SAME slot.
        final target = resolver.resolve(
          draggedKey: "a1",
          targetKey: "secB",
          targetPaintedY: 150.0,
          targetExtent: 50.0,
          pointerY: 155.0,
        );
        expect(
          target,
          isNotNull,
          reason:
              "above-a-section-header must chain to the previous "
              "section's tail, not die on the root veto",
        );
        expect(target?.parentKey, "secA");
        expect(
          target?.indexInFinalList,
          1,
          reason: "a1 removed from [a1, a2] and appended → live index 1",
        );
        expect(target?.depth, 1);

        // With an explicit depth hint the chain is directly addressable.
        final hinted = resolver.resolve(
          draggedKey: "a1",
          targetKey: "secB",
          targetPaintedY: 150.0,
          targetExtent: 50.0,
          pointerY: 155.0,
          preferredDepth: 1,
        );
        expect(hinted?.parentKey, "secA");
      },
    );

    testWidgets("above a left-boundary row without filters keeps the classic "
        "shallow slot as the default", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "secA", data: "A"),
        const TreeNode(key: "secB", data: "B"),
      ]);
      controller.setChildren("secA", [
        const TreeNode(key: "a1", data: "A1"),
        const TreeNode(key: "a2", data: "A2"),
      ]);
      controller.expand(key: "secA", animate: false);
      final resolver = DropZoneResolver<String>(treeController: controller);

      // No policy, no hint: above-secB stays the root-level slot — the
      // pre-fix behavior is the DEFAULT; the chain only engages via the
      // x hint or filter fallback.
      final target = resolver.resolve(
        draggedKey: "a1",
        targetKey: "secB",
        targetPaintedY: 150.0,
        targetExtent: 50.0,
        pointerY: 155.0,
      );
      expect(
        target?.parentKey,
        isNull,
        reason:
            "no hint → the classic above-target slot at the "
            "target's own depth",
      );
      expect(target?.depth, 0);
    });

    testWidgets("a policy that vetoes `into` collapses the row to the two-zone "
        "midpoint split instead of leaving a dead middle third", (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      final resolver = DropZoneResolver<String>(
        treeController: controller,
        // Flat-list policy: nothing may nest under a card.
        canAcceptDrop: ({required movingKey, newParent, index}) {
          return newParent == null;
        },
      );

      // Dragging "c" over "b" (painted 50..100): with `into` vetoed, the
      // row splits at its MIDPOINT — never a dead zone, and never an
      // `into` target.
      TreeDropTarget<String>? at(double pointerY) {
        return resolver.resolve(
          draggedKey: "c",
          targetKey: "b",
          targetPaintedY: 50.0,
          targetExtent: 50.0,
          pointerY: pointerY,
        );
      }

      final upperHalf = at(70.0);
      expect(
        upperHalf?.zone,
        TreeDropZone.above,
        reason:
            "t=0.4 is above the midpoint — previously the dead "
            "vetoed `into` third",
      );
      expect(upperHalf?.indexInFinalList, 1);

      final lowerHalf = at(80.0);
      expect(
        lowerHalf?.zone,
        TreeDropZone.below,
        reason: "t=0.6 is below the midpoint",
      );
      expect(
        lowerHalf?.indexInFinalList,
        2,
        reason:
            "below-b IS c's current position (c is b's next "
            "sibling) — the mirror no-op resolves as 'returns here'",
      );

      for (final pointerY in [55.0, 75.0, 95.0]) {
        expect(
          at(pointerY)?.zone,
          isNot(TreeDropZone.into),
          reason: "the veto must keep `into` unreachable everywhere",
        );
      }
    });

    testWidgets(
      "a policy that vetoes only INDEX 0 under a container degrades that "
      "row to a two-zone split, never a dead middle third",
      (tester) async {
        // The pin the `index: 0` precheck was missing. Every existing
        // "vetoes into" test uses a policy keyed on `newParent == null`,
        // which answers false for a concrete 0 AND for a shape-only null,
        // so none of them can tell the two prechecks apart. This one can:
        // it answers TRUE to a shape-only query and false only at index 0.
        final controller = TreeController<String, String>(
          vsync: tester,
          animationStyle: TreeAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);
        controller.setRoots([
          const TreeNode(key: "p", data: "P"),
          const TreeNode(key: "x", data: "X"),
        ]);
        controller.setChildren("p", [
          const TreeNode(key: "c1", data: "C1"),
          const TreeNode(key: "c2", data: "C2"),
        ]);
        controller.expandAll(animate: false);

        // Setup sanity: without an EXPANDED parent with live children the
        // below-on-expanded-parent rule is not armed, and that rule is one
        // of the two branches which commit to rawIndex 0 and return
        // unconditionally. Unarmed, this test could pass vacuously.
        expect(controller.visibleNodes, ["p", "c1", "c2", "x"]);
        expect(controller.isExpanded("p"), isTrue);
        expect(controller.hasLiveChildren("p"), isTrue);

        final resolver = DropZoneResolver<String>(
          treeController: controller,
          // Pin the first slot under p; every other slot stays legal.
          canAcceptDrop: ({required movingKey, newParent, index}) {
            return !(newParent == "p" && index == 0);
          },
        );
        // Setup sanity: the policy really does admit p at index 1, so a
        // dead row would be a resolver defect and not an honest refusal.
        expect(
          resolver.canAcceptDrop!(movingKey: "x", newParent: "p", index: 1),
          isTrue,
        );

        TreeDropTarget<String>? at(double t) {
          return resolver.resolve(
            draggedKey: "x",
            targetKey: "p",
            targetPaintedY: 0.0,
            targetExtent: 50.0,
            pointerY: t * 50.0,
          );
        }

        // 1. No dead band anywhere across the row. The thirds boundaries
        //    are sampled from both sides, because that is exactly where the
        //    gap flapped open and shut under the `index: null` precheck.
        for (final t in [0.05, 0.2, 0.32, 0.34, 0.49, 0.51, 0.65, 0.67, 0.9]) {
          expect(
            at(t),
            isNotNull,
            reason:
                "t=$t must resolve; a NULL here is the `index: null` "
                "regression: a dead `into` third and a dead "
                "below-on-expanded-parent band, neither with a fallback",
          );
        }

        // 2. The split is at the MIDPOINT, not at thirds.
        expect(at(0.4)?.zone, TreeDropZone.above);
        expect(at(0.6)?.zone, TreeDropZone.below);

        // 3. `into` is unreachable, which is the honest answer for a zone
        //    with exactly one index to offer when that index is vetoed.
        for (final t in [0.05, 0.4, 0.6, 0.9]) {
          expect(at(t)?.zone, isNot(TreeDropZone.into));
        }

        // 4. The gap still tracks the RESOLVED slot on both halves.
        expect(at(0.4)?.parentKey, isNull);
        expect(at(0.4)?.indexInFinalList, 0);
        expect(at(0.4)?.gapVisibleIndex, 0);
        expect(at(0.6)?.parentKey, isNull);
        expect(at(0.6)?.indexInFinalList, 1);
        expect(
          at(0.6)?.gapVisibleIndex,
          3,
          reason: "past p's whole visible subtree, not under p's own row",
        );
      },
    );
  });

  group("getIndexInParent scan budget (perf pin)", () {
    // Budgets below are EXACT and derived from the scripted layouts under
    // the live-index cache (step 2): one counter increment per
    // refresh-loop iteration, a refresh costs the touched list's FULL raw
    // length (it rebuilds every member's slot, not just the probed key's
    // prefix), and a cache-hit read costs ZERO. So a first-touch read
    // after a mutation counts the sum of the DISTINCT lists refreshed,
    // and a repeat read or resolve against unmutated lists counts
    // exactly 0, which is the whole payoff of the cache. Wide lists keep
    // the budgets discriminating: an accidental read of a list the
    // script never expects touched (an eager dragged-key read, a missed
    // cache hit) overshoots by that list's full width.

    testWidgets(
      "same-parent resolve is free once its lists are cached",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationStyle: TreeAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);
        controller.setRoots([
          const TreeNode(key: "s1", data: "S1"),
          const TreeNode(key: "s2", data: "S2"),
        ]);
        controller.setChildren("s1", [
          for (int i = 0; i < 30; i++) TreeNode(key: "i1_$i", data: "I1"),
        ]);
        controller.setChildren("s2", [
          for (int i = 0; i < 30; i++) TreeNode(key: "i2_$i", data: "I2"),
        ]);
        controller.expand(key: "s1");
        controller.expand(key: "s2");
        final resolver = DropZoneResolver<String>(treeController: controller);

        // First-touch pin: the read after setup's mutations refreshes
        // s1's whole 30-wide list, regardless of the key's position.
        controller.debugIndexInParentIterationCount = 0;
        expect(controller.getIndexInParent("i1_29"), 29);
        expect(controller.debugIndexInParentIterationCount, 30);

        // Warm pin: the resolve reads the target and the dragged key
        // from the SAME cached list; zero iterations, exact.
        controller.debugIndexInParentIterationCount = 0;
        final target = resolver.resolve(
          draggedKey: "i1_29",
          targetKey: "i1_0",
          targetPaintedY: 0.0,
          targetExtent: 50.0,
          pointerY: 5.0,
        );
        expect(target?.zone, TreeDropZone.above);
        expect(target?.parentKey, "s1");
        expect(target?.indexInFinalList, 0);
        expect(controller.debugIndexInParentIterationCount, 0);

        // A mutation invalidates: the same resolve after an unrelated
        // insert pays exactly one 30-wide refresh again, then is free.
        controller.insert(
          parentKey: "s2",
          node: const TreeNode(key: "i2_new", data: "N"),
          animate: false,
        );
        controller.debugIndexInParentIterationCount = 0;
        final again = resolver.resolve(
          draggedKey: "i1_29",
          targetKey: "i1_0",
          targetPaintedY: 0.0,
          targetExtent: 50.0,
          pointerY: 5.0,
        );
        expect(again?.zone, TreeDropZone.above);
        expect(controller.debugIndexInParentIterationCount, 30);
        controller.debugIndexInParentIterationCount = 0;
        resolver.resolve(
          draggedKey: "i1_29",
          targetKey: "i1_0",
          targetPaintedY: 0.0,
          targetExtent: 50.0,
          pointerY: 5.0,
        );
        expect(controller.debugIndexInParentIterationCount, 0);
      },
    );

    testWidgets("cross-parent resolves never scan the dragged key", (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "s1", data: "S1"),
        const TreeNode(key: "s2", data: "S2"),
      ]);
      controller.setChildren("s1", [
        for (int i = 0; i < 30; i++) TreeNode(key: "i1_$i", data: "I1"),
      ]);
      controller.setChildren("s2", [
        for (int i = 0; i < 30; i++) TreeNode(key: "i2_$i", data: "I2"),
      ]);
      controller.expand(key: "s1");
      controller.expand(key: "s2");
      final resolver = DropZoneResolver<String>(treeController: controller);

      // Above zone over the other section's first item: first touch
      // refreshes ONLY s2's 30-wide list. No warm-up reads precede this,
      // so an eager or accidental dragged-key read would refresh s1's
      // 30-wide home list on top and overshoot to 60.
      controller.debugIndexInParentIterationCount = 0;
      final above = resolver.resolve(
        draggedKey: "i1_29",
        targetKey: "i2_0",
        targetPaintedY: 0.0,
        targetExtent: 50.0,
        pointerY: 5.0,
      );
      expect(above?.zone, TreeDropZone.above);
      expect(above?.parentKey, "s2");
      expect(above?.indexInFinalList, 0);
      expect(controller.debugIndexInParentIterationCount, 30);

      // Identical repeat: everything cached, zero iterations.
      controller.debugIndexInParentIterationCount = 0;
      final repeat = resolver.resolve(
        draggedKey: "i1_29",
        targetKey: "i2_0",
        targetPaintedY: 0.0,
        targetExtent: 50.0,
        pointerY: 5.0,
      );
      expect(repeat?.zone, TreeDropZone.above);
      expect(controller.debugIndexInParentIterationCount, 0);

      // Into zone: rawIndex is the constant 0, no index is read at all.
      controller.debugIndexInParentIterationCount = 0;
      final into = resolver.resolve(
        draggedKey: "i1_29",
        targetKey: "i2_0",
        targetPaintedY: 0.0,
        targetExtent: 50.0,
        pointerY: 25.0,
      );
      expect(into?.zone, TreeDropZone.into);
      expect(into?.parentKey, "i2_0");
      expect(controller.debugIndexInParentIterationCount, 0);
    });

    testWidgets("below-zone boundary chain scans each level exactly once", (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      // r0 > c0 > d0 > e_0..e_19, with e_19 a triple right-boundary: last
      // child of d0, which is the only child of c0, which is the only
      // child of r0. rx serves two purposes: r0 is not the last root, so
      // the climb terminates on the later-live-sibling check, and rx is a
      // cross-parent dragged key whose home list must not be scanned.
      controller.setRoots([
        const TreeNode(key: "r0", data: "R0"),
        const TreeNode(key: "rx", data: "RX"),
      ]);
      controller.setChildren("r0", [const TreeNode(key: "c0", data: "C0")]);
      controller.setChildren("c0", [const TreeNode(key: "d0", data: "D0")]);
      controller.setChildren("d0", [
        for (int i = 0; i < 20; i++) TreeNode(key: "e_$i", data: "E"),
      ]);
      controller.expand(key: "r0");
      controller.expand(key: "c0");
      controller.expand(key: "d0");
      final resolver = DropZoneResolver<String>(treeController: controller);

      // Setup sanity: e_19 is visible. (Its index is asserted AFTER the
      // measured resolve; asserting it here would warm d0's list and
      // void the first-touch budget.)
      expect(controller.getVisibleIndex("e_19"), greaterThanOrEqualTo(0));

      controller.debugIndexInParentIterationCount = 0;
      final target = resolver.resolve(
        draggedKey: "rx",
        targetKey: "e_19",
        targetPaintedY: 0.0,
        targetExtent: 50.0,
        pointerY: 45.0,
      );
      // No depth hint: the deepest candidate (next sibling of e_19 under
      // d0) wins.
      expect(target?.zone, TreeDropZone.below);
      expect(target?.parentKey, "d0");
      expect(target?.indexInFinalList, 20);
      // First touch refreshes each DISTINCT list the boundary chain
      // reads, at its full length: d0's children (20) + c0's (1) + r0's
      // (1) + the roots (2, including rx). Duplicate reads of a level no
      // longer cost anything, so the budget pins one-refresh-per-list.
      expect(controller.debugIndexInParentIterationCount, 24);
      expect(controller.getIndexInParent("e_19"), 19);

      // Identical repeat: the whole chain is cached, zero iterations.
      controller.debugIndexInParentIterationCount = 0;
      final repeat = resolver.resolve(
        draggedKey: "rx",
        targetKey: "e_19",
        targetPaintedY: 0.0,
        targetExtent: 50.0,
        pointerY: 45.0,
      );
      expect(repeat?.zone, TreeDropZone.below);
      expect(controller.debugIndexInParentIterationCount, 0);
    });
  });
}
