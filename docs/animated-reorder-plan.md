# Animated Reorder for SyncedSliverTree — Implementation Plan

**Package:** widgets_extended
**Status:** proposed
**Date:** 2026-06-30
**Version target:** 0.0.24 → 0.0.25

## Problem

`SyncedSliverTree` animates insertions, removals, and reparenting (cross-parent
`moveNode`), but a **same-parent sibling reorder snaps** — no animation. Symptom
downstream: when a row's value changes so its server-sorted position moves, the
row updates in place with a hard cut instead of sliding to its new slot. (A
reparent — e.g. a row moving between two sections — already animates.)

## Root cause (verified against source)

The declarative sync re-sorts via the controller's `reorderChildren` /
`reorderRoots`, which mutate structure and notify but **never stage a FLIP slide
baseline**:

- `reorderChildren` — `lib/sliver_tree/tree_controller.dart:2238`
  (`_setChildList` → `_markVisibleOrderDirty` → `_notifyStructural`; comment
  "pure reorder — no builder output changes")
- `reorderRoots` — `lib/sliver_tree/tree_controller.dart:2199`
- Sync call sites: `lib/sliver_tree/tree_sync_controller.dart:341` (roots,
  step 6) and `:572` (children, step 5)

`moveNode` animates because it stages the baseline first:
`_stageSlideBaselineOnHosts(...)` (`tree_controller.dart:2407`) → mutate →
`_markVisibleOrderDirty` → `_notifyStructural`. The next layout consumes the
baseline and FLIP-slides every shifted row. `moveNode` already supports a
same-parent index change (`:2376-2383` no-ops only when the index is unchanged),
so the engine is fully capable of animating a reorder — the reorder methods just
don't invoke the staging.

## Fix

Give `reorderChildren` / `reorderRoots` an `animate` flag (default **`true`**, to
match `moveNode` / `insert` / `insertRoot`) that stages the FLIP baseline before
the structural mutation. A pure reorder is the simplest FLIP case: all affected
rows stay under the same expanded parent, all visible before and after, no depth
change, no phantom anchors — so staging the baseline plus the existing notify is
sufficient.

### Correctness invariants

- **Verified premise:** for a pure reorder, `moveNode` finishes with
  `_markVisibleOrderDirty()` + `_notifyStructural(affectedKeys: const {})`
  (`tree_controller.dart:2540-2558`, `affected` is empty when no depth/hasChildren
  change) — identical to what `reorderChildren`/`reorderRoots` already do. Adding
  the missing `_stageSlideBaselineOnHosts` before the mutation makes the sequence
  match `moveNode`, so the slide is guaranteed.
- **Stage before mutate** — the baseline must capture pre-reorder painted
  positions.
- **Two-tier gate (staging ≠ rebuild):** stage the baseline ONLY when the
  reorder is *strictly visible* —
  `_isExpandedKey(parent) && _ancestorsExpandedFast(parent)`. This is a strict
  subset of the existing `needsVisibleRebuild` (which also fires for a child
  mid-animation under a *collapsed* parent). Staging only on the strictly-visible
  case (a) avoids a pointless/broken slide for a collapsed reorder, (b) avoids
  tangling with an in-flight exit animation (which `moveNode` cancels/reverts but
  `reorderChildren` does not), and (c) guarantees `_markVisibleOrderDirty` also
  runs (visible ⊂ needsVisibleRebuild) → the next layout consumes the baseline →
  no stranded baseline. `reorderRoots` calls `_markVisibleOrderDirty`
  unconditionally, so it needs no visibility gate.
- **`animationDuration == Duration.zero`:** skip staging entirely (explicit
  guard). Note this diverges from `moveNode`, which has no early guard and relies
  on a downstream no-op — the explicit guard is the more conservative, correct
  choice and matches expand/collapse/insert. Slide duration = `animationDuration`
  (consistent with the tree's other animations), not a separate `slideDuration`.

## Blast radius

`reorderChildren` / `reorderRoots` have callers beyond the sync controller that
currently rely on the snap:

- `lib/sectioned_sliver_list/sectioned_list_controller.dart:324,454` — sectioned
  list reorders. Animated reorder is desirable → take the new default.
- `lib/sliver_tree/tree_reorder_controller.dart:294,296` — **drag-and-drop**
  commit. The gesture is already the animation → pass `animate: false`
  explicitly (verify a slide doesn't fight the dragged item).
- Sync controller (`:341`, `:572`) — keep passing `animate: animate` explicitly
  so the **initial** sync stays a snap; only rebuilds animate.
- ~40 test call sites — most assert order/index, which survive because the FLIP
  slide is **paint-only** (layout settles immediately at the new structural
  positions). At risk: painted-offset / slide-delta assertions in the `slide_*`
  tests, and any "no slide after reorder" assertion.

## Implementation steps

1. `tree_controller.dart` `reorderChildren`: add `{bool animate = true}`. Compute
   `visible = _isExpandedKey(parent) && _ancestorsExpandedFast(parent)` BEFORE
   `_setChildList` (expansion is order-independent). Stage the baseline when
   `animate && visible && animationDuration != Duration.zero`. Keep the broader
   `needsVisibleRebuild` (`visible || child-mid-animation`) for the existing
   `_markVisibleOrderDirty` call. Sketch:

   ```dart
   void reorderChildren(TKey parentKey, List<TKey> orderedKeys,
       {bool animate = true}) {
     // ...existing validation → pendingChildren, liveChildSet...
     final visible = _isExpandedKey(parentKey) && _ancestorsExpandedFast(parentKey);
     if (animate && visible && animationDuration != Duration.zero) {
       _stageSlideBaselineOnHosts(duration: animationDuration, curve: animationCurve);
     }
     _setChildList(parentKey, [...orderedKeys, ...pendingChildren]);
     bool needsVisibleRebuild = visible;
     if (!needsVisibleRebuild) {
       for (final child in _childListOf(parentKey)!) {
         if (_hasOperationGroup(child) ||
             _activeBulkGroup?.members.contains(child) == true ||
             _hasStandalone(child)) { needsVisibleRebuild = true; break; }
       }
     }
     if (needsVisibleRebuild) _markVisibleOrderDirty();
     _notifyStructural(affectedKeys: const {});
   }
   ```
2. `tree_controller.dart` `reorderRoots`: add `{bool animate = true}`; stage the
   baseline when `animate && animationDuration != Duration.zero`, before the
   `_roots` rewrite (roots are depth-0 and `reorderRoots` always marks the
   visible order dirty, so no visibility gate is needed).
3. `tree_sync_controller.dart:341,572`: pass `animate: animate`.
4. `tree_reorder_controller.dart:294,296`: pass `animate: false` (verify).
5. `pubspec.yaml`: bump `0.0.24 → 0.0.25`; add a CHANGELOG entry.

## Test plan

- **Baseline:** run the full suite green before edits.
- **New test** (`test/sliver_tree/animated_reorder_test.dart`): on a mounted
  tree, a `reorderChildren` and a `reorderRoots` with `animate: true` install
  non-zero slide deltas on the shifted rows (mirror `animated_move_to_test.dart`
  / `animation_transitions_test.dart`); `animate: false` installs none.
- **Regression:** re-run the full suite + `dart analyze`. Fix fallout: pump where
  a test now needs to advance the animation; pass `animate: false` where a test
  specifically asserts the snap path.

## Downstream (clarity-express app)

No app code changes. After publishing, bump `widgets_extended` to `^0.0.25`. The
workspace name-edit resort then animates automatically — it flows through the
declarative `reorderChildren` path, and the existing
`_isCurrentRoute ? 300ms : Duration.zero` gating animates it on-screen only.

## Acceptance

- New reorder-animation test passes; full suite + `dart analyze` green.
- Drag-reorder behavior unchanged (snap).
- App (post-bump): a same-section rename slides the row to its sorted position
  instead of cutting.

## Risks

- `slide_*` tests may need adjustment for the new reorder slides — expected;
  surfaced and handled via the suite.
- Drag-reorder settle: verify `animate: false` at the drag site is correct;
  fall back to animating there only if a slide is actually desired.
