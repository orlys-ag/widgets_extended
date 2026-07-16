# Post-Implementation Review — Follow-up Fixes Plan

**Package:** widgets_extended (`lib/sliver_tree`)
**Status:** planned
**Date:** 2026-07-15
**Baseline:** the uncommitted working tree implementing
`sliver_tree_audit_2026_07_15_plan.md` (on top of commit `8ee57bd`), `flutter test`
green (611 passed / 4 skipped), `flutter analyze` at 52 findings (baseline before the
audit work was 62 — net improvement, but a handful are newly introduced; see R9).

## How this plan was produced

A correctness review of the full audit-implementation diff (~2,200 changed lines in
`lib/`, 21 new + 15 modified test files): a hunk-by-hunk pass over the controller,
animation, order-buffer, and render diffs, plus two parallel deep reviews (consumer
layer: sync/reorder/synced-widget; test-oracle validity across all 36 new files).
Every finding below was **verified against source** (file:line evidence) before being
included; candidate findings that did not survive verification were discarded (among
them: coalescing microtask interleavings, slide-stamp cleanup races, the 5.4
contiguity capture across Steps 1–2, bulk-continuation extent pops, semantics/hit-test
ordering, `endDrag` finally-ordering, `_childrenExactMatch` skipped side effects).

**Repro-test methodology** (house convention, `plans/audit_repros/README.md`): each
behavioral item is test-driven — write the test asserting EXPECTED behavior, confirm it
FAILS on the current tree, fix, confirm it PASSES, keep it in `test/sliver_tree/` as
the regression test. Doc/hygiene items are verified by `flutter analyze` and reading.

## Item format

Each item: **Issue** (evidence + concrete failure), **Solution** (chosen design, with
rejected alternatives where relevant), **Dependencies**, **Verification**. Items are
listed in implementation order. Every wave ends with the full suite green.

## Suggested wave order

```
Wave 1 (behavioral):   R1 → R2 → R3          (independent files; R1 first — highest severity)
Wave 2 (test quality): R6 → R7 → R8
Wave 3 (docs/hygiene): R4 → R5 → R9 → R10    (batchable; analyzer-verified)
```

---

# Phase 1 — Behavioral fixes

## R1 — `deactivate()` drag backstop fires `notifyListeners`/`setState` inside a build scope (HIGH)

**Category:** bug (debug/test crash-grade; release mostly benign) · **Repro:** new,
to be written (see Verification)

**Issue.** The 3.2 lifecycle backstop
(`sliver_reorderable_tree.dart:286-291`) synchronously calls
`reorderController.cancelDrag()` (which fires `notifyListeners()`) and then
`widget.state._onDragEnd()` (which calls `setState` on the ancestor
`_SliverReorderableTreeState`) from inside `deactivate()`. `deactivate()` only ever
runs inside a `BuildOwner.buildScope`. Concrete scenario — the exact "node removed
mid-drag" case the backstop's own comment claims to cover:

1. A drag session is active on row X (X pinned via `pinNode`).
2. X is removed and purged (`getNodeData(X) == null`). The drag pin cannot protect
   it: dead-node GC (`sliver_tree_element.dart:319-347`) deliberately ignores
   `isNodeRetained` (there is nothing left to build) and deactivates X's row element
   inside `owner!.buildScope(this, ...)` (line 339).
3. `deactivate()` → `cancelDrag()` → `notifyListeners()`:
   - `_onControllerChanged` (`sliver_reorderable_tree.dart:159`) → `_onDragEnd()` →
     `setState` (line 199) on an **ancestor** element while `_debugBuilding` is true →
     "setState() or markNeedsBuild() called during build" — caught by
     `ChangeNotifier`, reported via `FlutterError` (fails any test that hits it).
   - `_DropIndicatorState._onControllerChanged` (line 438) → second reported error;
     since the first `_onDragEnd` threw before `_removeIndicator()`, the overlay
     entry also leaks at this point.
4. Back in `deactivate()`, the **direct** `widget.state._onDragEnd()` call repeats the
   `setState` → this throw is **uncaught**, unwinding out of the GC's `buildScope`:
   `super.deactivate()` never runs for the row element, and the remaining `evictNow`
   entries in that GC pass are skipped.

A milder variant (tree swapped out mid-drag,
`condition ? SliverReorderableTree(...) : other`): the ancestor state is already
inactive so its `setState` no-ops, but the still-active `_DropIndicatorState` in the
root overlay gets `setState` during build → one reported `FlutterError` per
occurrence.

**Solution.** Split the backstop into a synchronous flag flip plus deferred cleanup:

- In `deactivate()`, keep only `_isDraggingThisRow = false` synchronous, then defer
  the session teardown via
  `SchedulerBinding.instance.addPostFrameCallback` (NOT `scheduleMicrotask` — a
  microtask can still land inside the same frame's build/layout window when
  deactivation happens during the normal build phase; post-frame is the first point
  guaranteed outside every build scope).
- Inside the callback, re-validate before acting (the world may have moved on):
  `reorderController.draggedKey == widget.nodeKey` still (a new session may have
  started — see the 3.4 ownership test), and the reorder controller not disposed.
  Then `cancelDrag()`; do **not** call `widget.state._onDragEnd()` directly — after
  the R1 fix it is redundant: `cancelDrag`'s `notifyListeners` already drives
  `_onControllerChanged → _onDragEnd`, and outside a build scope that path is safe.
  (The direct call existed only to cover the listener being gone; guard instead with
  `widget.state.mounted` and call it only if the listener didn't already clear the
  scope — simplest: call `_onDragEnd()` after `cancelDrag()` iff
  `widget.state.mounted`, which is itself now safe post-frame.)
- Keep the comment honest: document that teardown is deferred one frame and why.

Rejected alternatives:
- *Make dead-node GC consult `isNodeRetained`/pins*: rejected — a purged node has no
  data to build; retaining a dead element indefinitely is worse than the bug, and the
  session must end anyway when its row's key is gone.
- *Wrap the sync calls in `try/catch`*: hides the framework contract violation
  instead of fixing it; the listener-side `setState`s would still be reported errors
  in tests.
- *`WidgetsBinding.instance.scheduleMicrotask`-style "defer if building" check via
  `SchedulerBinding.instance.schedulerPhase`*: fragile — deactivation from the GC's
  post-frame `buildScope` reports `SchedulerPhase.postFrameCallbacks`, so a phase
  check misclassifies exactly the primary scenario. Unconditional post-frame is
  simpler and always correct.

**Dependencies.** None (single file; interacts with 3.2/3.4 semantics — the
re-validation guard preserves the 3.4 session-ownership behavior).

**Verification.**
1. New `test/sliver_tree/drag_backstop_deactivate_test.dart`, two cases:
   - *removed mid-drag*: mount `SliverReorderableTree` with a shared
     `TreeReorderController`, long-press-drag row "a", `remove(key: "a",
     animate: false)`, pump two frames (purge + GC post-frame). EXPECT: no
     `FlutterError` (flutter_test fails automatically on reported errors — the
     unfixed tree fails here), `reorder.isDragging == false`, and a sibling dead row
     removed in the same GC pass is actually unmounted (proves the pass wasn't
     aborted).
   - *tree swapped mid-drag*: start a drag, `pumpWidget` a layout without the tree.
     EXPECT: no reported errors, session cancelled, overlay indicator entry removed
     (`find.byType` on the indicator widget → nothing).
2. Confirm both FAIL on the current tree with the predicted "setState() or
   markNeedsBuild() called during build" mechanism, then pass post-fix.
3. Existing `external_cancel_drag_test.dart` (3.4 ownership) and
   `sliver_reorderable_tree_widget_test.dart` stay green — the deferred path must not
   commit or cancel a session it no longer owns.

## R2 — `ScrollOrchestrator` teardown is single-slot; concurrent scrolls defeat the 1.9 dispose guarantee (MEDIUM)

**Category:** bug (edge case: overlapping animated scrolls; debug assert + listener/
controller leak) · **Repro:** new, to be written

**Issue.** `_scroll_orchestrator.dart:337-338` — a second concurrent
`animateScrollToKey(...animated...)` overwrites `_activeScrollProgress` /
`_activeFollower`; and the `finally` at lines 378-379 nulls both slots
unconditionally, even when they hold a *different* scroll's resources (first scroll
finishing while the second is in flight strands the second's teardown handles).
Consequences with two overlapping animated scrolls: `dispose()` tears down only the
slot's current occupant — the other scroll's `AnimationController` stays active, so
the vsync State's active-Ticker assert (the exact assert item 1.9 fixed) can still
fire, and its follower listener leaks until the controller's listener list dies.

**Solution.** Make animated scrolls **single-flight**: starting a new animated scroll
cancels the in-flight one. This matches user intent (the newer target wins — two
concurrent scroll animations fighting over `position.jumpTo` was never meaningful)
and makes the single slot correct by construction:

- Introduce a small per-invocation session record
  (`_ActiveScroll { AnimationController progress; VoidCallback follower;
  bool cancelled; bool tornDown; }`).
- At the start of `_animatedConcurrentScroll`, if a record exists: mark it
  `cancelled`, tear it down **synchronously** (remove follower, dispose progress,
  set `tornDown`) — same teardown `dispose()` performs — then install the new record.
- The wait loop checks `record.cancelled || _disposed` (per-session token, not just
  the global flag) and returns `false` on cancellation.
- The `finally` tears down idempotently via `tornDown` and clears the slot **only if
  it still holds this invocation's record** (identity check) — never a successor's.
- `dispose()` unchanged in spirit: mark `_disposed`, tear down the current record
  idempotently.

Rejected alternative: *a `Set` of concurrent sessions, all allowed to run*: keeps the
old racing-`jumpTo` behavior, which is visually garbage and doubles the teardown
surface for no user value.

**Dependencies.** None (single file; extends 1.9).

**Verification.**
1. Extend `test/sliver_tree/scroll_orchestrator_dispose_test.dart`:
   - *concurrent + dispose*: start animated scroll #1 (long `duration`), pump a few
     frames, start scroll #2 without awaiting #1, pump, then unmount the tree widget
     (vsync State dispose runs `controller.dispose`). EXPECT: no active-Ticker
     assert, both futures resolve (`#1 == false`). Fails on the current tree with the
     Ticker assert.
   - *supersede*: start #1, start #2, pump to completion. EXPECT: `#1` resolves
     `false` (cancelled), `#2` resolves `true`, final offset is #2's target.
2. Existing immediate-mode and single-scroll dispose tests stay green.

## R3 — Complete audit 6.6: relocation re-inserts still fire both notification channels (LOW)

**Category:** contract/perf (double rebuild of one row; violates the documented
"structural subsumes data — never fire both" convention) · **Repro:** extend existing

**Issue.** `tree_controller.dart:1726` and `:2174` — in both `insertRoot` and
`insert` data-update branches, `_notifyNodeDataChanged(node.key)` fires
unconditionally *before* the relocate decision. The 6.6 change correctly made the
no-relocation case data-channel-only, but the `wantsRelocate` path now fires **data
AND structural** for the same row — the exact double refresh 6.6 removed, on the
rarer path. The new comment ("structural refresh, which subsumes the data channel's
row refresh") already states the intended contract; the code doesn't honor it.

**Solution.** Move the `_notifyNodeDataChanged` call after the relocate decision in
both branches:

- No relocation → data channel only (unchanged).
- Same-parent relocation → structural (`affectedKeys: {node.key}`) only.
- **Different-parent path (delegates to `moveNode`) — keep the data fire before
  delegating.** `moveNode`'s structural notification is *targeted*: its
  `affectedKeys` includes the moved subtree only when the depth changed (plus
  old-parent/new-parent chevron keys). For a same-depth cross-parent move the moved
  key itself may be absent from `affectedKeys`, so without the data fire the
  overwritten payload would never reach the mounted row. Do not "fix" this by
  broadening `moveNode`'s affected set — that would pay a subtree walk on every move
  for a payload concern that only the insert-with-payload path has.
- Same treatment in the pending-deletion resurrect branches is **out of scope**: the
  C022 comments there (`:1691`, `:2143`) deliberately document firing both channels
  because `_cancelDeletion`'s structural fire is a full-refresh (null) on some paths
  and listeners of only one channel exist; leave as-is.

**Dependencies.** None (extends 6.6; touches the same two branches).

**Verification.**
1. Extend `test/sliver_tree/data_only_reinsert_notification_test.dart`: in both
   existing tests, at the relocation step additionally assert `dataFires` did **not**
   increment (structural only), and assert the new payload is still readable
   (`getNodeData(...).data`). Add a third case: `insert` with a different
   `parentKey` (moveNode delegation) at equal depth — assert the data channel fired
   and the built row shows the new payload after pump. Relocation assertions fail on
   the current tree (`dataFires` increments); fix; green.
2. Full suite green (the element consumes both channels; watch
   `synced_noop_rebuild_test.dart` and the sync-controller suites for reliance on the
   double fire — none expected, the sync layer reads controller state, not channels).

---

# Phase 2 — Test-quality fixes

## R6 — `repaint_boundary_test.dart` default-on oracle is tautological (MEDIUM, test-only)

**Category:** test coverage (the positive direction of audit 5.10 is untested)

**Issue.** `repaint_boundary_test.dart:53-61` asserts
`find.ancestor(of: row, matching: find.byType(RepaintBoundary))` → `findsWidgets`.
A `MaterialApp` route always contains framework-inserted `RepaintBoundary`s above the
sliver (`_ModalScope` wraps every page), so the assertion passes even if
`addRepaintBoundaries` is completely broken. It only "failed first" under TDD because
the named parameter didn't compile at baseline. The opt-out test in the same file
already uses the correct inside-the-sliver scoping.

**Solution.** Extract the opt-out test's scoping walk into a helper
(`bool _hasRowBoundaryInsideSliver(WidgetTester tester, Key rowKey)`: nearest
`RepaintBoundary` ancestor of the row, then `visitAncestorElements` to check it sits
**below** the `SliverTree` element) and assert it `isTrue` in the default-on test and
`isFalse` (for any boundary found) in the opt-out test — making the two tests exact
mirrors.

**Dependencies.** None.

**Verification.** Discriminating-power check (the test-fix analogue of "fails
first"): temporarily flip the default-on harness to `addRepaintBoundaries: false` and
confirm the fixed assertion FAILS; restore; confirm both tests pass. Full suite green.

## R7 — `sync_cycle_validation_test.dart` inert message matcher (TRIVIAL, test-only)

**Issue.** Lines 47-51: `.having((e) => e.message.toString(), "message",
contains("a"))` — the single letter "a" appears in virtually any English error text,
so the refinement adds zero discrimination over the bare `isA<ArgumentError>()`.

**Solution.** Read the actual `ArgumentError` message produced by the 2.3 guards and
match a discriminating fragment (the quoted/delimited offending key, or the
"cycle"/"repeated" wording — whichever the message actually contains). If the message
doesn't name the key, prefer improving the guard's message (include the offending key
— CLAUDE.md: include validation that makes errors actionable) and then match it.

**Verification.** Mutate the matcher to a wrong fragment locally → test fails
(discriminates); restore; green.

## R8 — Vestigial empty `addTearDown(() {})` (TRIVIAL, test-only)

**Issue.** `animation_notify_coalescing_test.dart:59` — an empty teardown, presumably
a forgotten `removeAnimationListener`. Harmless (dispose clears listeners) but dead.

**Solution.** Replace with the intended
`addTearDown(() => controller.removeAnimationListener(listener))` (or delete the line
if the listener variable isn't in scope for teardown). Verification: file's tests
green.

---

# Phase 3 — Documentation & hygiene

## R4 — `_syncChildrenImpl` step-4 comment states the opposite of the shipped 2.2 behavior (LOW, doc + changelog)

**Issue.** `tree_sync_controller.dart:577-583` still says pending-deletion nodes are
"intentionally NOT auto-cancelled here", cross-referencing `_syncRootsImpl` step 4
"for the rationale" — but 2.2 rewrote that rationale to the opposite policy
(desired state is authoritative) and the children path's behavior flipped with it: a
sync whose desired list still contains a mid-exit key now **resurrects** it via
`insert(..., preservePendingSubtreeState: true)` (line 534). The behavior change was
a deliberate 2.2 decision, coherent with the roots-side doc (lines 242-249) and the
live-by-default read APIs; only this comment survived from the old world.

**Solution.**
1. Rewrite the step-4 comment to match the roots-side rationale: desired state is
   authoritative; a desired key that is mid-exit gets resurrected; callers that want
   an imperative `removeItem` to stick must derive their mirrored state from live
   reads (which exclude pending-deletion rows), which is what
   `getLiveChildren`/`liveItemsOf` already give them.
2. Add a `CHANGELOG.md` entry under the next version: "TreeSyncController /
   SectionedListController: syncs now diff against controller truth; a desired list
   that still contains a removed (mid-exit) key resurrects it. Derive mirrored state
   from live reads to preserve imperative removals." (The 2.2 shift shipped without a
   changelog note; this closes that gap.)

**Dependencies.** None. **Verification.** Reading + `sync_controller_truth_test.dart`
already pins the resurrect behavior — confirm it documents the same policy the new
comment states.

## R5 — Doc/annotation misattachment around `debugOrderResetIndexAllCount` (TRIVIAL)

**Issue.** `tree_controller.dart:321-341` — the new getter + `debugFullConsistencyChecks`
were inserted between `debugAssertVisibleSubtreeSizeConsistency`'s doc comment +
`@visibleForTesting` and its declaration. Result: `debugOrderResetIndexAllCount`
carries two `@visibleForTesting` annotations and the wrong leading doc ("Debug-only
forwarder preserved for the existing fuzz test surface…"), while
`debugAssertVisibleSubtreeSizeConsistency` lost both its doc and its annotation.

**Solution.** Reorder: give each member exactly its own doc + one annotation —
"Debug-only forwarder…" doc + `@visibleForTesting` back onto
`debugAssertVisibleSubtreeSizeConsistency`; the reset-count doc +
single `@visibleForTesting` on the getter. **Verification:** `flutter analyze`,
dartdoc sanity by reading.

## R9 — New analyzer lints introduced by the audit work (TRIVIAL)

**Issue / Solution (one line each):**
- `_animation_coordinator.dart:400` — `fullExtentOfNid` overrides
  `AnimationReader.fullExtentOfNid` without `@override` → add the annotation.
- `audit_repro_f1_test.dart:24` — unused `package:flutter/widgets.dart` import →
  remove.
- `audit_repro_f44_test.dart:1` — dangling library doc comment → add a `library;`
  directive after it (house pattern used by the other repro files).
- `audit_repro_f45_test.dart:9-10` — unescaped `<...>` in doc comment reads as HTML →
  wrap the generic in backticks.
- `bulk_reentry_continuation_test.dart:18` — unnecessary `flutter/animation.dart`
  import (covered by material) → remove. Same for
  `independent_timelines_test.dart:18` while in there.

**Verification.** `flutter analyze` shows no findings in these files; total count
drops below 52 with zero new findings anywhere in `lib/` or the new tests.

## R10 — Stale docref to the deleted `_phantomExitEdge` map (TRIVIAL)

**Issue.** `render_sliver_tree.dart:1388` — `_exitGhostPaintedBaseScrollSpace`'s doc
says "Anchor unmounted with a registered `[_phantomExitEdge]`", a map deleted by 6.3.
(The mention at line 546 is an intentional historical note — leave it.)

**Solution.** Reword to "Anchor unmounted with a persisted [ViewportEdge] on its
[_ExitGhost] record". **Verification:** reading; `dart doc` reference resolution via
analyzer.

---

# Explicitly accepted (no action)

- **5.8 one-tick staleness:** the O(1) `structuralYOf` resolver reads render-layer
  offsets that `normalizeForViewport` (early in `performLayout`,
  `render_sliver_tree.dart:1989`) can observe one animation-tick stale, where the old
  code prefix-summed live controller extents. Only shifts the edge-ghost re-promotion
  threshold by ≤1 frame — cosmetic, inherent to the O(1) design, and the exact O(index)
  fallback remains for unwired registries. Optionally note this in the resolver's doc
  while touching the file for R10.
- **Cyclic-input hang shape in `sync_cycle_validation_test.dart`:** on a regression,
  the cyclic case would hang the shard (synchronous walk; `package:test` timeouts
  can't interrupt a single-threaded loop) rather than fail cleanly. Informational —
  the guard itself is the fix, and a test-side depth guard is impossible.
- **`_emptiedWhileCollapsed` retention across direct controller mutations:** the one
  skippable effect of the 2.5 exact-match early-out; no scenario produces observably
  wrong behavior (suppression only applies to a parent the user genuinely collapsed,
  which is the designed outcome).
