/// Regression tests for the 2026-07-29 review, item 2 (part 2a):
/// [TreeController.setReorderPreview] memoizes on RESULT geometry
/// `(draggedNid, gapIndex, lift, structureGeneration, snap mode)` so an
/// identical re-send — every pointer event and autoscroll tick while the
/// pointer dwells in one slot — skips the O(visibleNodeCount) target loop
/// and map allocation. Pinned via
/// [TreeController.debugPreviewInstallCount] (full computations only;
/// memo hits do not increment).
///
/// The memo compares computed geometry, not caller inputs: two different
/// target expressions of the same slot skip (case: geometry-not-inputs),
/// while an equal-geometry structural swap inside the shifted span — the
/// one change geometry can't see — recomputes via the structure
/// generation. The validity flag (not `_preview.hasActive`) keeps
/// empty-target installs memoizable: hovering the dragged block's own
/// slot produces no engine entries, and is the initial state of every
/// drag.
library;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

TreeController<String, String> _sixRoots(
  WidgetTester tester, {
  required TreeAnimationStyle style,
}) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: style,
  );
  controller.setRoots([
    for (int r = 0; r < 6; r++) TreeNode(key: "r$r", data: "R$r"),
  ]);
  return controller;
}

void main() {
  testWidgets("identical re-send memo-skips; slot change recomputes",
      (tester) async {
    final controller =
        _sixRoots(tester, style: TreeAnimationStyle.disabled);
    addTearDown(controller.dispose);

    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r4",
      gapBelowTarget: false,
    );
    expect(controller.debugPreviewInstallCount, 1,
        reason: "first resolve must compute");
    expect(controller.hasActiveSlides, isTrue,
        reason: "setup: the preview must have installed held offsets");

    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r4",
      gapBelowTarget: false,
    );
    expect(controller.debugPreviewInstallCount, 1,
        reason: "identical re-send (pointer dwell) must memo-skip");

    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r5",
      gapBelowTarget: false,
    );
    expect(controller.debugPreviewInstallCount, 2,
        reason: "a different slot must recompute");

    controller.clearReorderPreview(animate: false);
  });

  testWidgets(
      "same slot expressed through a different target/edge pair memo-skips "
      "(geometry, not inputs)", (tester) async {
    final controller =
        _sixRoots(tester, style: TreeAnimationStyle.disabled);
    addTearDown(controller.dispose);

    // gapIndex 4, expressed as "above r4"...
    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r4",
      gapBelowTarget: false,
    );
    // ...and as "below r3": same draggedNid, same gapIndex, same lift.
    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r3",
      gapBelowTarget: true,
    );
    expect(controller.debugPreviewInstallCount, 1,
        reason: "two expressions of the same gap slot are one geometry — "
            "the second must memo-skip");

    controller.clearReorderPreview(animate: false);
  });

  testWidgets(
      "equal-geometry structural swap inside the shifted span recomputes "
      "via the structure generation", (tester) async {
    final controller =
        _sixRoots(tester, style: TreeAnimationStyle.disabled);
    addTearDown(controller.dispose);

    // Dragged r1 (index 1), gap at index 4: span r2, r3 shifts by -lift.
    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r4",
      gapBelowTarget: false,
    );
    expect(controller.debugPreviewInstallCount, 1);

    // Swap a row INSIDE the span while preserving every geometric memo
    // component: remove r2, insert y at the same live index. draggedIndex
    // stays 1, r4 stays at index 4 (gapIndex 4), lift is untouched (the
    // dragged block is not involved). Only the structure generation sees
    // this — which is exactly why it is part of the key.
    controller.remove(key: "r2", animate: false);
    controller.insertRoot(TreeNode(key: "y", data: "Y"), index: 2);

    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r4",
      gapBelowTarget: false,
    );
    expect(controller.debugPreviewInstallCount, 2,
        reason: "an equal-geometry mutation must recompute via the "
            "structure-generation conjunct — a memo without it would "
            "false-skip and leave y unshifted");
    expect(controller.getSlideDelta("y"), isNot(0.0),
        reason: "the recompute was necessary: the swapped-in row sits in "
            "the shifted span and must carry a preview offset");

    controller.clearReorderPreview(animate: false);
  });

  testWidgets("clear-then-restart recomputes (no stale-memo skip)",
      (tester) async {
    final controller =
        _sixRoots(tester, style: TreeAnimationStyle.disabled);
    addTearDown(controller.dispose);

    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r4",
      gapBelowTarget: false,
    );
    controller.clearReorderPreview(animate: false);
    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r4",
      gapBelowTarget: false,
    );
    expect(controller.debugPreviewInstallCount, 2,
        reason: "clearReorderPreview must invalidate the memo — the "
            "restarted preview's first install may not be skipped");
    expect(controller.hasActiveSlides, isTrue,
        reason: "the restarted preview must actually be installed");

    controller.clearReorderPreview(animate: false);
  });

  testWidgets(
      "own-slot dwell (empty target map, no engine entries) memoizes — "
      "the initial state of every drag", (tester) async {
    final controller =
        _sixRoots(tester, style: TreeAnimationStyle.disabled);
    addTearDown(controller.dispose);

    // "Below r0" with r1 dragged IS r1's own slot: every shift cancels,
    // the target map is empty, and the engine holds no entries.
    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r0",
      gapBelowTarget: true,
    );
    expect(controller.debugPreviewInstallCount, 1);
    expect(controller.hasActiveSlides, isFalse,
        reason: "setup: the own-slot state installs no offsets — the "
            "state a hasActive-guarded memo could never memoize");

    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r0",
      gapBelowTarget: true,
    );
    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r0",
      gapBelowTarget: true,
    );
    expect(controller.debugPreviewInstallCount, 1,
        reason: "own-slot re-sends must memo-skip despite the engine "
            "holding no entries (validity flag, not hasActive)");

    controller.clearReorderPreview(animate: false);
  });

  testWidgets(
      "animated path: dwell during and after the gap animation memo-skips; "
      "an identical-geometry snap re-send does NOT skip", (tester) async {
    final controller = _sixRoots(
      tester,
      style: const TreeAnimationStyle(
        makeRoom: TreeAnimationSpec(
          duration: Duration(milliseconds: 200),
          curve: Curves.linear,
        ),
      ),
    );
    addTearDown(controller.dispose);

    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r4",
      gapBelowTarget: false,
    );
    expect(controller.debugPreviewInstallCount, 1);

    // Mid-animation dwell.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r4",
      gapBelowTarget: false,
    );
    expect(controller.debugPreviewInstallCount, 1,
        reason: "identical re-send mid-animation must memo-skip (the "
            "engine would ignore it anyway; the memo saves the O(N) loop)");

    // Settled-hold dwell.
    await tester.pump(const Duration(milliseconds: 200));
    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r4",
      gapBelowTarget: false,
    );
    expect(controller.debugPreviewInstallCount, 1,
        reason: "identical re-send against the settled hold must memo-skip");

    // Identical geometry, but resolved to SNAP: the engine's snap branch
    // has no retarget early-out (it forces instant arrival), so the memo
    // must not absorb the mode change.
    controller.setReorderPreview(
      draggedKey: "r1",
      targetKey: "r4",
      gapBelowTarget: false,
      duration: Duration.zero,
    );
    expect(controller.debugPreviewInstallCount, 2,
        reason: "a zero-duration (snap) re-send with identical geometry "
            "is observable behavior and must recompute, not skip");

    controller.clearReorderPreview(animate: false);
    await tester.pumpAndSettle();
  });
}
