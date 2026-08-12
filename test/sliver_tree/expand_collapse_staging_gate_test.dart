/// Repro and pin suite for item 8 of the 2026-07-29 architecture review
/// (`plans/2026-07-29-sliver-tree-arch-perf-review.md`): slide-baseline
/// staging in `expand()`/`collapse()` must be gated by the O(1)
/// [TreeController.hasActiveSlides] check before doing any per-row work,
/// and `collapse()` must walk its visible descendants exactly once.
///
/// Three defects, two repro pins and one guard:
///
/// - `expand()` materializes the FULL structural descendant list and probes
///   a slide delta per row even when nothing is animating; the first test
///   pins zero probes AND zero walks for the idle case.
/// - `collapse()` computes `_getVisibleDescendants(key)` twice back to back
///   (once for staging, once for removal); the second test pins exactly one
///   walk. The dedup is sound because the walker does not gate on the
///   collapsed key's own expansion flag (documented at
///   `_getVisibleDescendantsInto`'s declaration) and nothing between the
///   two former call sites mutates the visible order.
/// - The GUARD pins that the gate does not over-fire: with any composed
///   slide activity, the per-row probe loop still runs, which is what
///   decides whether a baseline is actually staged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const int _childCount = 300;

TreeController<String, String> _buildController(
  WidgetTester tester, {
  TreeAnimationStyle animationStyle = TreeAnimationStyle.disabled,
}) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: animationStyle,
  );
  controller.setRoots([
    const TreeNode(key: "p", data: "P"),
    const TreeNode(key: "q", data: "Q"),
  ]);
  controller.setChildren("p", [
    for (int i = 0; i < _childCount; i++) TreeNode(key: "c$i", data: "C$i"),
  ]);
  return controller;
}

void _resetCounters(TreeController<String, String> controller) {
  controller.debugSlideBaselineStagingProbeCount = 0;
  controller.debugDescendantWalkCount = 0;
  controller.debugVisibleDescendantsWalkCount = 0;
}

void main() {
  group("expand/collapse staging is O(1)-gated when idle", () {
    testWidgets(
      "idle expand of a large collapsed subtree performs zero staging "
      "probes and zero descendant walks",
      (tester) async {
        final controller = _buildController(tester);
        addTearDown(controller.dispose);

        expect(
          controller.hasActiveSlides,
          isFalse,
          reason: "setup: the tree must be idle, or the gate rightly passes",
        );
        expect(
          controller.isExpanded("p"),
          isFalse,
          reason: "setup: the subtree must start collapsed",
        );

        _resetCounters(controller);
        controller.expand(key: "p");

        expect(
          controller.isExpanded("p"),
          isTrue,
          reason: "sanity: the expand must actually happen",
        );
        expect(
          controller.visibleNodes.length,
          2 + _childCount,
          reason: "sanity: the children must enter the visible order",
        );
        expect(
          controller.debugSlideBaselineStagingProbeCount,
          0,
          reason:
              "an idle expand must not probe a single row for a live "
              "slide; the O(1) hasActiveSlides gate answers the question "
              "for all of them at once",
        );
        expect(
          controller.debugDescendantWalkCount,
          0,
          reason:
              "an idle expand must not materialize the structural "
              "descendant list either; the staging row source is lazy and "
              "must never be invoked when the gate is closed",
        );
      },
    );

    testWidgets(
      "idle collapse walks its visible descendants exactly once and "
      "performs zero staging probes",
      (tester) async {
        final controller = _buildController(tester);
        addTearDown(controller.dispose);
        controller.expand(key: "p");
        expect(
          controller.visibleNodes.length,
          2 + _childCount,
          reason: "setup: the subtree must be expanded before collapsing",
        );
        expect(
          controller.hasActiveSlides,
          isFalse,
          reason: "setup: the tree must be idle",
        );

        _resetCounters(controller);
        controller.collapse(key: "p");

        expect(
          controller.isExpanded("p"),
          isFalse,
          reason: "sanity: the collapse must actually happen",
        );
        expect(
          controller.visibleNodes.length,
          2,
          reason: "sanity: the children must leave the visible order",
        );
        expect(
          controller.debugVisibleDescendantsWalkCount,
          1,
          reason:
              "one collapse performs exactly ONE visible-descendants "
              "walk, shared by baseline staging and the removal logic; "
              "two walks is the duplicated work this item removes",
        );
        expect(
          controller.debugSlideBaselineStagingProbeCount,
          0,
          reason: "an idle collapse must not probe any row for a live slide",
        );
      },
    );

    testWidgets(
      "GUARD: with composed slide activity the per-row probe loop still "
      "runs on expand",
      (tester) async {
        // Passes before and after the fix. Pins that the O(1) gate does
        // not over-fire: when hasActiveSlides is true, the per-row probes
        // must run, because they are what decides whether a baseline is
        // actually staged. The slide lives on an unrelated root, so every
        // probe answers false and no baseline is staged, which keeps the
        // budget exact: one probe per structural descendant of the
        // expanded key.
        final controller = _buildController(
          tester,
          animationStyle: const TreeAnimationStyle(
            expandCollapse: TreeAnimationSpec(
              duration: Duration(milliseconds: 300),
              curve: Curves.linear,
            ),
            enterExit: TreeAnimationSpec(
              duration: Duration(milliseconds: 300),
              curve: Curves.linear,
            ),
            reorderSlide: TreeAnimationSpec(
              duration: Duration(milliseconds: 300),
              curve: Curves.linear,
            ),
          ),
        );
        addTearDown(controller.dispose);

        controller.animateSlideFromOffsets(
          {"q": (y: 100.0, x: 0.0)},
          {"q": (y: 0.0, x: 0.0)},
        );
        expect(
          controller.hasActiveSlides,
          isTrue,
          reason: "setup: the installed slide must open the gate",
        );

        _resetCounters(controller);
        controller.expand(key: "p");

        expect(
          controller.isExpanded("p"),
          isTrue,
          reason: "sanity: the expand must actually happen",
        );
        expect(
          controller.debugSlideBaselineStagingProbeCount,
          _childCount,
          reason:
              "with the gate open, every structural descendant must be "
              "probed exactly once (no early break: the slide is on an "
              "unrelated root, so no probe answers true)",
        );

        await tester.pumpAndSettle();
      },
    );
  });
}
