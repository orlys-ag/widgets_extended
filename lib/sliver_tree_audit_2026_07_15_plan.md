# Sliver Tree Audit — Findings & Remediation Plan

**Package:** widgets_extended (`lib/sliver_tree`)
**Status:** implemented (all waves, 2026-07-15) — every repro promoted to
`test/sliver_tree/`; full suite green. 5.1's guard 3 (drop the cumulative
entirely) deliberately remains behind the planned debug-assert soak.
**Date:** 2026-07-15
**Baseline:** commit `8ee57bd`, clean tree, `flutter test` green (547 passed / 4 skipped), `flutter analyze` clean on `lib/`.

## How this plan was produced

Four parallel deep audits (state layer, render layer, animation subsystem, sync/reorder
layer) over all 17,900 lines of `lib/sliver_tree`, cross-checked against the full test
suite. Every finding below was **verified against source** (file:line evidence) and, where
marked, by a **failing repro test**. The 14 pre-existing repro tests in
`plans/audit_repros/` (stage-1 triage, 2026-07-04) were re-run at this baseline: all
still fail as predicted, so their findings are folded in here. One new repro was added
during this audit (`audit_repro_s1_test.dart`) and verified to fail with the predicted
mechanism. Candidate findings that did not survive verification were discarded (each
audit's rejected list included, among others: ScrollOrchestrator disposal, bulk-mirror
drift, contiguous-path clobbering, reentrancy in `collapseAll`, zero-duration NaN,
sticky hit-test overshoot).

**Repro-test methodology** (house convention, `plans/audit_repros/README.md`): each repro
asserts the EXPECTED behavior and fails on unfixed code. To implement an item: copy its
repro into `test/sliver_tree/`, confirm it fails, fix, confirm it passes, keep it as the
regression test.

## Item format

Each item: **Issue** (evidence + concrete failure), **Solution** (chosen design, with the
alternatives that were considered and rejected), **Dependencies**, **Verification**.
Items are listed in **implementation order**; interdependent items are explicitly
sequenced. Phases group related subsystems; later phases may start before earlier ones
finish *except where a dependency is stated*.

## Dependency graph (summary)

```
1.2 (index-space contract) ──► 2.1 (sync order fixes) ──► 2.2 (controller-as-truth diffing)
                          └──► 3.3 (endDrag hardening)
3.2 (drag pinning) ───────────► 3.3
4.3 (clip prune) ─────────────► 4.4 (snapshot/paint parity)   [same subsystem, ordered]
Phase-1/2/3/4 correctness ────► 6.1 (teardown dedup)          [dedup last so fixes land on live copies]
4.x ghost lifecycle ──────────► 5.7 (slide ticks paint-only)  [Step 0a/0b timing entangled]
5.2 ◄──────────────────────────► 4.7 (same hit-test loop — implement together)
```

This graph is a **summary of the load-bearing edges only**; each item's
"Dependencies" line is authoritative and includes additional same-file ordering edges
(1.5→1.7, 1.8→1.9, 1.1→5.4, 1.2→{5.5, 6.6}, 2.1→{2.2, 2.4, 2.5}, 3.3→3.4,
5.1→5.8, {1.1, 5.4}→6.2, {4.3–4.5, 5.9}→6.3, {1.1, 1.4, 1.6}→6.1).

---

# Phase 1 — Controller / state-layer correctness

## 1.1 Dangling parent nids on surviving mid-exit descendants → ABA cache corruption (CRITICAL)

**Category:** bug (silent state corruption) · **Repro:** `plans/audit_repros/audit_repro_s1_test.dart` (fails at baseline with `Bad state: _subtreeSizeByNid[1] (key=k) = 0, expected 1`)

**Issue.** `_finalizeAnimation`'s deletion branch purges an exiting parent (releasing its
nid) but deliberately keeps descendants that still run their own exit animation
(`_tree_controller_animation.dart:688-695`: `if (_isPendingDeletion(desc) &&
!_hasStandalone(desc)) _purgeNodeData(desc);` — animating descendants are skipped). The
survivor's `_parentByNid` slot still points at the freed nid; `NodeStore.release`
(`_node_store.dart`) clears only the released nid's own slots. The code relies on
`keyOf(freedNid) == null` making later parent lookups return null — but the
`NodeIdRegistry` free list recycles nids (LIFO), so any `insert`/`insertRoot`/
`setChildren` during the survivor's remaining exit re-assigns that nid to an unrelated
node K. When the survivor then finalizes, `_parentKeyOfKey` resolves **K**, and the
visible-loss bookkeeping runs `_order.bumpFromSelf(K_nid, -1)`
(`_tree_controller_animation.dart:661-684`) — decrementing an unrelated node's
visible-subtree-size chain. The cache is globally desynced; `subtreeSizeOf` drives
insert positioning (`tree_controller.dart:2092-2111`, `_insertNewNodeAmongSiblings`), so
subsequent inserts land at wrong visible indices — see the `insert()` fast path (`tree_controller.dart:2092-2111`) and
`_insertNewNodeAmongSiblings` (`_tree_controller_animation.dart:727-756`), both of
which position by `_order.subtreeSizeOf`. Silent in release; debug asserts fire.
The window is realistic: exit `speedMultiplier` (up to 10×,
`_tree_controller_animation.dart:588-598`) makes a partially-entered parent finalize
long before its full-extent child.

Two more vectors share the root cause (no recycling needed): `remove(orphan,
animate: false)` walks the freed nid in `_purgeAndRemoveFromOrder` Step 1
(`_tree_controller_helpers.dart:383-392`) and hits `bumpFromSelf`'s freed-slot assert
(`_visible_order_buffer.dart:241-247`; silent break in release); `moveNode(orphan, …)`
fires `handleParentChanged` with the stale old-parent nid
(`_visible_order_buffer.dart:361-373`).

**Solution.** In `_finalizeAnimation`'s deletion branch, after collecting `descendants`
and purging the non-animating ones, **sever the parent pointer of every kept descendant
whose structural parent was purged in this pass**: collect purged keys into a set during
the walk; for each kept descendant whose parent is in that set, call
`_setParentKey(desc, null)` wrapped in
`_order.runWithSubtreeSizeUpdatesSuppressed(...)`. The suppression is load-bearing:
`handleParentChanged` early-returns under suppression, so the sever does not re-decrement
ancestor chains that the visible-loss block already decremented. After severing, the
survivor's own finalize takes the `parentKey == null` path (`_roots.remove` no-op, purge
self + own descendants) — exactly the behavior today's code gets when the freed nid
happens *not* to be recycled. Depth staleness on severed nodes is harmless (they are
invisible and exiting).

*Alternatives audited and rejected:* (a) defer releasing the parent's nid until the last
animating descendant finalizes — requires refcounting nid lifetimes across animation
sources, far more invasive, and leaves the freed-nid-walk vectors open for the
grandparent chain; (b) make `NodeIdRegistry` generational (nid+generation stamps) — fixes
the ABA read but not the `bumpFromSelf` freed-slot walk, and touches every nid-keyed
array in the package. Severing is local, matches the existing "orphan" semantics, and
closes all three vectors at once.

**Dependencies:** none. Do first — every later state-layer test run is more trustworthy
once this corruption source is closed.
**Verification:** promote `audit_repro_s1_test.dart`; re-run
`visible_subtree_size_invariant_fuzz_test.dart`, `purge_*` tests,
`remove_from_order_zombie_leak_test.dart`.

## 1.2 One index-space contract: `index` parameters are live-space everywhere

**Category:** bug + architecture · **Repros:** `audit_repro_f1_test.dart` (controller),
`audit_repro_f43_test.dart` (drag-drop), `audit_repro_f33_test.dart` (sync — see 2.1)

**Issue.** `moveNode` consumes `index` in two different index spaces: the same-parent
no-op guard compares against the **live** index (`getIndexInParent`, documented
live-space; `tree_controller.dart:2400-2407`) while the insertion writes into the
**full** sibling list that still contains pending-deletion entries
(`tree_controller.dart:2493-2509`). `insert`/`insertRoot` apply explicit indices to the
full list the same way (`:2077-2081`, `:1727-1735`, plus the pending-relocation and
live-relocation branches at `:1633-1642`, `:1694-1708`, `:1987-1996`, `:2045-2058`).
Meanwhile every read-side API (`getIndexInParent`, `liveRootKeys`, `getLiveChildren`,
`reorderRoots`/`reorderChildren` validation) and both shipped consumers
(`TreeReorderController.endDrag` → `indexInFinalList`, `TreeSyncController`'s Fenwick
`targetIndex`) operate in live space. Concrete failures with full list
`[X(pending), A, B]` (live `[A, B]`): `moveNode(A, parent, index: 1)` silently produces
no visible change and settles to the **wrong permanent order**; a drag-drop above a live
sibling lands one slot too high whenever an exiting sibling precedes the slot
(f43); `moveNode(B, parent, index: 1)` intending full-space is silently dropped by the
live-space no-op guard.

**Solution.** Declare **live-space** as the one public index space (it is what every
read API and both consumers already speak) and convert at the write boundary. Add one
private helper:

```dart
/// Full-list insertion position such that, after insertion, the node sits at
/// [liveIndex] among live (non-pending-deletion) entries. O(1) when no
/// pending deletions exist; O(list) otherwise.
int _liveIndexToFullInsertIndex(List<TKey> fullList, int liveIndex)
```

returning the full-list index of the live entry currently at live position `liveIndex`
(insert lands directly above that live sibling — intervening exiting rows stay above the
new node, matching drop-indicator semantics), or `fullList.length` when `liveIndex >=`
live count. Fast path: `if (_anim.pendingDeletionCount == 0) return
liveIndex.clamp(0, fullList.length);`. Apply at all **ten** explicit-index consumption
sites in `insertRoot`/`insert`/`moveNode` — fresh insert (`:1727-1735`, `:2077-2081`),
same-location live-relocation (`:1694-1708`, `:2045-2058`), pending-relocation
same-parent (`:1633-1642`, `:1987-1996`), pending-relocation **different-parent**
(`:1625-1631`, `:1978-1984` — easy to miss; this is the resurrection path
`TreeSyncController` exercises), and `moveNode`'s two insertions (`:2493-2509`).
The comparator path (`_sortedIndex`) already returns
full-space positions correctly and is untouched. Document the contract on all three
public methods ("`index` is the position among live siblings; exiting siblings are
skipped").

*Alternatives audited and rejected:* (a) full-space everywhere — would require every
caller (reorder controller, sync Fenwick logic, user code following
`getIndexInParent`) to convert, inverting more call sites than it fixes and breaking the
documented `TreeDropTarget.indexInFinalList` contract; (b) fixing only the callers —
leaves the trap in the public API and the `moveNode` guard/insert disagreement in place.

**Dependencies:** none. Blocks 2.1 and 3.3.
**Verification:** promote `audit_repro_f1_test.dart` and `audit_repro_f43_test.dart`
(f43 should pass with **no reorder-layer change** — it validates the passthrough);
re-run `move_into_pending_parent_test.dart`, `insert_after_move_in_batch_test.dart`,
reorder suite.

## 1.3 `insert()` / `setChildren()` guard a pending-deletion parent with assert-only

**Category:** bug (release-mode corruption) · **Repro:** `audit_repro_f3_test.dart`

**Issue.** `insert` and `setChildren` reject a mid-exit parent only via `assert`
(`tree_controller.dart:1957-1962`, `:1796-1802`) while `moveNode` enforces the identical
precondition with a runtime `throw StateError` (`:2379-2385`) — whose comment claims it
"mirrors the policy insert(parentKey:) already enforces". In release builds the assert
vanishes: a child inserted under a mid-exit parent survives the parent's purge with a
dangling parent nid and leaks its registry entry forever (the exact corruption family of
1.1).

**Solution.** Replace both asserts with runtime `StateError` throws in all build modes,
with the same message text moveNode uses. This is a deliberate behavior change
(silent-corrupt → throw) and is the desired one.

**Known test impact:** `tree_controller_test.dart:1994-1997` ("asserts to prevent
orphaned state") asserts `throwsA(isA<AssertionError>())` for exactly this call —
rewrite its expectation to `StateError`. (`move_into_pending_parent_test.dart:43`
already accepts `anyOf(AssertionError, StateError)` and survives unchanged.)

**Dependencies:** none (same functions as 1.2 — implement in the same pass to avoid
churn).
**Verification:** promote `audit_repro_f3_test.dart`; update the expectation above.

## 1.4 `animationDuration = Duration.zero` mid-flight permanently strands animations and leaks pending deletions

**Category:** bug (leak + freeze) · **Repros:** `audit_repro_f2_test.dart`,
`audit_repro_f23_test.dart`

**Issue.** `StandaloneAnimator._runTick` bails on zero duration without completing or
clearing anything (`_standalone_animator.dart:219-223`): rows freeze at partial extent,
pending-deletion nodes are never purged (the standalone finalize path is the *only*
purge path for standalone exits), and `hasActiveAnimations` stays true forever —
permanently engaging the render layer's animating-mode gates (sticky throttle, eviction
deferral). Reachable directly from public API: the setter is public and
`SyncedSliverTree.didUpdateWidget` forwards `widget.animationDuration` changes
(`synced_sliver_tree.dart:688-690`). The setter's docstring
(`tree_controller.dart:80-98`) claims the opposite ("the standalone ticker re-reads this
on every tick, so its animations adjust on the next frame"). Restoring a non-zero
duration later does **not** recover (nothing restarts the ticker).

**Solution.** In the zero-duration branch of `_runTick`: instead of stop-and-abandon,
**snap every active state to completion** (`state.progress = 1.0; state.updateExtent(curve)`
for all active nids), collect all keys into the completed list, fire `_onTick(allKeys)`
(which drives `_finalizeAnimation` → purge → structural notify through the existing
handler), then stop the ticker. Semantics: "zero duration = animations complete
instantly," which matches every mutator's `if (animationDuration == Duration.zero)
animate = false` convention and the setter's documented intent. Also fix the setter doc:
in-flight bulk/op-group `AnimationController`s do **not** re-time a running simulation
when `duration` is reassigned (duration is read at the next `forward()`/`reverse()`);
state the actual behavior (groups finish at their old rate; standalone completes
immediately).

*Alternative audited and rejected:* finalizing synchronously inside the setter — the
setter can be called from `didUpdateWidget` (build phase); routing completion through the
next tick keeps purge + structural notification out of build, at the cost of one frame
of latency, and covers all entry points (including a getter-driven zero from
`AnimationCoordinator`'s duration getter) in one place.

**Dependencies:** none.
**Verification:** promote `audit_repro_f2_test.dart` + `audit_repro_f23_test.dart`
(covers both the immediate-completion and the restore-nonzero contract).

## 1.5 `expandAll` / `collapseAll` read a stale visible order inside `runBatch`

**Category:** bug

**Issue.** Every other mutator flushes the deferred in-batch order rebuild on entry
(`insert` `tree_controller.dart:1956`, `insertRoot` `:1614`, `expand` `:2635`,
`collapse` `:2861` — each with a rationale comment). `expandAll`/`collapseAll` do not:
`expandAll` reads `!_order.contains(childId)` while collecting `nodesToShow` (`:3015`)
*before* its mid-way flush (`:3070`), and `collapseAll` collects
`_getVisibleDescendants(rootId)` (`:3170`, reads `_order.contains`) with no flush at
all. Inside `runBatch(() { moveNode(...); expandAll(); })`, children whose visibility
was changed by the earlier in-batch mutation are misclassified: omitted from
`nodesToShow` (pop in at full extent, never join the bulk group) or mis-collected into
`nodesToHide`. The order buffer self-heals at batch exit, but the animation-membership
decisions made from stale data persist.

**Solution.** Add `_ensureVisibleOrder()` at the top of both methods, mirroring the
existing pattern and comment. (The mid-way flush in `expandAll` stays — it serves the
post-mutation re-read.)

**Dependencies:** none.
**Verification:** new regression test — `runBatch` with `moveNode` + `expandAll`
asserting bulk membership of moved-in children; re-run `runbatch_deferred_rebuild_test.dart`,
`batch_notification_test.dart`.

## 1.6 Second `collapseAll` mid-flight disposes the live bulk group and snaps rows to full extent

**Category:** bug (visual)

**Issue.** `collapseAll` called while a bulk collapse is mid-flight (e.g. double-tap on
a "collapse all" button): the bulk-members sweep re-adds the collapsing members to
`nodesToHide` (`tree_controller.dart:3206-3215`); the reverse branch is skipped because
it requires `pendingRemoval.isEmpty` (`:3260-3262`); the else branch calls
`_anim.bulk.createGroup(..., initialValue: 1.0)` (`:3285-3289`), which **disposes the
in-flight group first** (`_bulk_animator.dart:201-226`) and re-adds every member to a
fresh group at value 1.0. Rows painting at `full × 0.5` jump to `full × 1.0` in one
frame, then re-collapse from scratch. Symmetric weaker case: `expandAll` mid-bulk-expand
with new nodes takes the fresh-group branch (`:3123-3127`) and pops half-expanded
members to full. Single-node paths carefully capture mid-flight extents
(`_captureAndRemoveFromGroups`); the bulk paths don't.

**Solution.** Make both re-entry paths **continuation-aware**: if the active bulk group
is already animating in the requested direction, keep it (no `createGroup`, no value
reset) — existing members continue from their current extent. Genuinely **new** nodes
must NOT join a mid-flight group (they would pop from 0 to `full × currentValue` on
join); route them through `_startStandaloneEnterAnimation` /
`_startStandaloneExitAnimation` instead — the same policy the reverse branches already
apply to `nodesToReverseExit`. Only create a fresh group when there is no active group
or the active group runs the opposite direction (already handled by the reverse
branches). This mirrors how `expand`/`collapse` Path 1 reuses an existing op-group
rather than reinstalling.

*Alternative audited and rejected:* capturing each member's mid-flight extent into
standalone exits before creating the fresh group — preserves continuity but converts a
single scalar bulk animation into N per-node animations (defeating the bulk fast path)
for a case where simply continuing the existing group is strictly better.

**Dependencies:** none. Note for 6.1: this touches bulk-membership logic — land before
the teardown dedup.
**Verification:** new test: `collapseAll(); pump(150ms); collapseAll();` asserting no
member's extent increases frame-over-frame; same for `expandAll` (extent never
decreases). Re-run `animation_transitions_test.dart`.

## 1.7 `expandAll` fails to animate descendants revealed through already-expanded interior nodes

**Category:** bug (visual, parity)

**Issue.** `expandAll` harvests only the **direct children** of nodes whose expansion
flag flips (`tree_controller.dart:3010-3019`). A hidden interior node B that is already
`expanded == true` (state deliberately preserved by `collapse()` — `:2848-2852`) becomes
visible together with its children when ancestor A expands, but B's children never enter
`nodesToShow` → never join the bulk group → render at full extent from frame one while
everything around them animates. `expand(key: A)` on the identical structure animates
the whole revealed subtree (`_flattenSubtree`, `:2754`) — the two APIs disagree.
Same gap applies at the `maxDepth` boundary (DFS stops descending, so deeper
already-visible-through-expansion subtrees are skipped).

**Solution.** When a node K is added to `nodesToExpand`, harvest not just its direct
children but the **expansion-gated flatten of each child** (children, plus descendants
reachable through already-expanded nodes — exactly `_flattenSubtree(child,
includeRoot: true)` per child not in `_order`). This matches `expand()`'s semantics.
The DFS already visits these nodes; the change is to collect at the boundary where
descent would otherwise stop (already-expanded children are not re-pushed as
`nodesToExpand`, and depth-limited nodes are not descended into — both need the flatten
harvest).

**Dependencies:** after 1.5 (same function; 1.5's flush changes what `_order.contains`
sees).
**Verification:** new test: collapse A (B under it stays expanded=true) → `expandAll()`
→ assert B's children are bulk members on frame 1; same with `maxDepth`.

## 1.8 `animateScrollToKey` (immediate mode) clamps against the pre-expansion `maxScrollExtent`

**Category:** bug · **Repro:** `audit_repro_f24_test.dart`

**Issue.** Immediate-mode ancestor expansion enlarges the scrollable content
synchronously, but the target computation clamps against `position.maxScrollExtent`
*before* the framework has laid out the enlarged sliver
(`_scroll_orchestrator.dart:195-212`) — the scroll stops at the stale max (e.g. exactly
100.0) and the target row stays far below the viewport.

**Solution.** In the immediate path, when `ensureAncestorsExpanded` actually expanded
anything, `await SchedulerBinding.instance.endOfFrame` (scheduling a frame if none is
pending) once before reading `position` and computing/clamping the target. The method is
already async, and the animated-concurrent path already uses exactly this wait + a final
precise snap. Bail out (return false) if `scrollController` loses its clients across the
await.

*Alternative audited and rejected:* not clamping (let `animateTo` overshoot and settle)
— triggers overscroll glow/ballistic correction with clamping physics and lands
imprecisely; the one-frame wait is deterministic.

**Dependencies:** none.
**Verification:** promote `audit_repro_f24_test.dart`.

## 1.9 `_animatedConcurrentScroll` has no cancellation; offstage trees busy-schedule frames forever; dispose mid-flight trips the active-Ticker assert

**Category:** bug (resource/lifecycle)

**Issue.** The completion loop (`_scroll_orchestrator.dart:314-335`) is
`while (true) { ...; await SchedulerBinding.instance.endOfFrame; }` with exit conditions
that can never fire when the tree goes offstage mid-scroll (`TickerMode(false)` mutes
the `AnimationController`'s ticker → never completes; `hasClients` stays true) —
`endOfFrame` then pumps frames at full rate indefinitely. Neither
`TreeController.dispose()` nor `ScrollOrchestrator.dispose()` (`:359-365`, explicit
no-op) can cancel the in-flight call; disposing the vsync State while `scrollProgress`
is live throws the standard active-Ticker FlutterError in debug. The `follower`
animation listener and the controller stay registered for the loop's lifetime.

**Solution.** Add a cancellation flag to `ScrollOrchestrator` set from its `dispose()`,
checked each loop iteration; wrap the loop body in `try/finally` that removes the
`follower` listener and disposes `scrollProgress` on every exit path (it already does
on the normal paths — make it structural). On cancellation, exit without the final
snap. **Wiring gap (load-bearing):** `TreeController.dispose()`
(`tree_controller.dart:3459-3473`) currently never calls `_scroll.dispose()` — add
that call, and since `_scroll` is `late final` (lazily created), avoid instantiating
it just to dispose it (e.g. track a `_scrollCreated` flag or make the field nullable);
without this wiring the cancellation flag is never set on controller disposal and the
item's verification test still fails.

**Dependencies:** none (same file as 1.8 — order 1.8 first, it's the verified repro).
**Verification:** new test: start animated-mode scroll, dispose the controller
mid-flight inside the test's tick loop → no FlutterError, listener count returns to 0.

## 1.10 `BulkAnimationData.containsMember` throws `TypeError` on the inactive sentinel

**Category:** bug · **Repro:** `audit_repro_f45_test.dart`

**Issue.** `BulkAnimationData.inactive<TKey>()` returns a const
`BulkAnimationData<Never>` cast to `BulkAnimationData<TKey>` (`types.dart:392-397`).
`containsMember(TKey key)` (`types.dart:454-459`) triggers Dart's generic covariance
check against the **actual** type argument (`Never`) before the body runs — any call
with a real key throws, despite the docs promising "Always false on an invalid
snapshot."

**Solution.** Change the parameter type to `Object?`
(`bool containsMember(Object? key)`) — `Set.contains` already accepts `Object?`, the
covariance check disappears, and the zero-allocation const sentinel is preserved.
`containsMemberNid` is unaffected.

*Alternative audited and rejected:* allocating a properly-typed empty snapshot per
`inactive()` call — sacrifices the documented zero-per-call-allocation contract on a
per-layout call for no benefit.

**Dependencies:** none.
**Verification:** promote `audit_repro_f45_test.dart`.

## 1.11 Phantom-anchor maps staged even when no render host participates

**Category:** bug (stale state, low)

**Issue.** `moveNode(animate: true)` ignores the boolean from
`_stageSlideBaselineOnHosts` and unconditionally populates
`_pendingPhantomAnchors`/`_pendingExitPhantomAnchors`
(`tree_controller.dart:2430-2459`, `:2547-2565`). With no participating host (controller
not mounted / detached), nothing drains them; a *later* animated mutation's consume
applies anchors recorded for a long-finished move to the wrong slide cycle.

**Solution.** Capture the fan-out result; populate the anchor maps only when at least
one host is participating. (The anchor computation itself can stay where it is — it
must read pre-mutation state.)

**Dependencies:** none.
**Verification:** unit test — `moveNode(animate: true)` with no attached render object,
then mount + unrelated animated move → `takePendingPhantomAnchors()` returns null at
consume time.

---

# Phase 2 — Sync layer (`TreeSyncController` / `SyncedSliverTree`)

## 2.1 Deferred cross-parent moves break same-sync sibling finalization: reorder throws (f32) / insertion misorders permanently (f33)

**Category:** bug (crash + permanent misorder) · **Repros:**
`audit_repro_f32_test.dart`, `audit_repro_f33_test.dart`

**Issue.** Two facets of one root cause — `_syncChildrenImpl` finalizes each parent
against its **own tracking mirror** while deferred cross-parent moves have not yet
happened:

- **f32 (crash):** step 1 defers removal of a child desired under another parent
  (`tree_sync_controller.dart:441-453`), but step 5 immediately calls
  `reorderChildren(parentKey, liveDesiredKeys)` (`:563-573`). The deferred child is
  still a live child of `parentKey`, so `reorderChildren`'s all-build-modes validation
  throws `ArgumentError` (`tree_controller.dart:2264-2273`) — propagating out of
  `SyncedSliverTree.didUpdateWidget`. Iteration-order dependent (fires when the source
  parent is DFS-visited before the destination): a heisenbug. `_syncRootsImpl` was
  explicitly fixed for exactly this (its reorder runs *after* the recursive pass,
  `:251-258`); the per-parent path never got the same treatment.
- **f33 (silent misorder):** `targetIndex` is computed against the tracking `remaining`
  list, applied by `insert` to the raw sibling list (see 1.2), and step 5's repair never
  fires because it compares tracking against tracking (`liveRemaining` from `remaining`,
  not from `controller.getLiveChildren`). Step 6 then overwrites tracking with the
  desired order (`:576`), so an identical re-sync is a no-op and the wrong order
  **persists forever**.

**Issue (adjacent, same fix):** an insertion into a parent that still hosts a deferred
child computes Fenwick indices that don't account for the deferred key, landing new
children one slot off until the repair pass runs.

**Solution.** Two coordinated changes in `_syncChildrenImpl`:

1. Track this sync's **deferred keys** per parent (children skipped in step 1 because
   they are globally desired elsewhere).
2. Replace step 5's tracking-vs-tracking comparison with **controller truth**: build
   `orderedKeys = liveDesiredKeys + (controller live children not in desired — i.e. the
   deferred movers, in their current relative order, appended)`; compare against
   `controller.getLiveChildren(parentKey)` (minus exiting keys, as today) and call
   `reorderChildren` when different. Appending the deferred keys satisfies
   `reorderChildren`'s exact-live-set validation (fixes f32); they are moved out later
   in the same batch when their destination parent syncs, so the transient tail position
   is invisible. Comparing against controller truth makes the repair actually fire
   (fixes f33's persistence — and, combined with 1.2's live-space `insert`, the
   insertion lands correctly in the first place; the repair becomes a safety net).

**Dependencies:** 1.2 (live-space `insert`/`moveNode` is what makes the Fenwick
`targetIndex` land correctly when exiting siblings are present).
**Verification:** promote `audit_repro_f32_test.dart` + `audit_repro_f33_test.dart`;
re-run the full sync suite (`tree_sync_controller_test.dart`,
`sync_duplicate_keys_test.dart`, `rapid_reparent_*`, `synced_sliver_tree_test.dart`).

## 2.2 Sync tracking mirror silently diverges from the controller — the package's own reorder layer is incompatible with its sync layer

**Category:** architecture (with concrete bug consequences)

**Issue.** `TreeSyncController` diffs exclusively against its private
`_currentRoots`/`_currentChildren` mirror (`tree_sync_controller.dart:64-68`). Any
structural mutation that bypasses the sync layer desynchronizes it with no detection:
(a) `TreeItemView.controller` is a documented escape hatch — one `controller.remove()`
and subsequent syncs diff against fiction (a re-added key is judged "retained" and never
re-inserted); (b) **`TreeReorderController` commits drops directly via
`moveNode`/`reorderChildren`/`reorderRoots`** (`tree_reorder_controller.dart:296-312`) —
composing drag-reorder with a `SyncedSliverTree` (the obvious "reorderable synced tree"
app) diverges tracking on every drop, after which the next sync silently mis-diffs.
Nothing warns about the combination, and the only resync hook (`initializeTracking`) is
called just on a `preserveExpansion` flip (`synced_sliver_tree.dart:698-705`).

**Solution (staged).**
1. **Derive the diff's "current" inputs from the controller** instead of the mirror:
   in `_syncRootsImpl` use `controller.liveRootKeys` and in `_syncChildrenImpl` use
   `controller.getLiveChildren(parentKey)` in place of `_currentChildren[parentKey]`.
   **Live-filtered, not `getChildren`** — the full list includes pending-deletion
   (exiting) children, and treating those as "current" would put them in `toRemove`
   and re-issue `remove()` on already-exiting rows, restarting their exit animations.
   The live view is the correct analog of what the tracking mirror approximated. The
   mirror's remaining legitimate jobs — expansion memory and the auto-expand old/new
   comparison — keep working from `snapshotCurrentChildren()`, which can also be
   derived from the controller (live-children walk). This removes the entire
   divergence class at the root: external mutations are simply the new baseline for
   the next diff, which is the intuitive semantics.
2. Document explicitly on both classes that after step 1, direct controller mutations
   compose safely with sync-driven updates (and add a test doing drag-commit →
   `syncRoots` round-trip).

*Alternatives audited and rejected:* (a) subscribing the sync controller to the
structural channel to invalidate tracking — adds a listener lifecycle and still leaves a
window where tracking is stale within a batch; (b) documenting the incompatibility only
— leaves the flagship composition (reorderable synced tree) broken.

**Dependencies:** 2.1 (step-5 controller-truth comparison is the first slice of this;
land 2.1 first, then generalize the inputs).
**Verification:** new test: `SyncedSliverTree` + `TreeReorderController` — drag-commit a
reorder, then re-sync with server data reflecting the new order → no mis-diff, no
duplicate/lost rows.

## 2.3 Unvalidated `childrenOf` in `.nodes` mode / raw `syncRoots`: a cycle hangs the UI thread

**Category:** bug (robustness)

**Issue.** Four of five `SyncedSliverTree` input modes validate cycles/duplicates and
throw `ArgumentError`; the `.nodes` mode and any direct
`TreeSyncController.syncRoots(childrenOf:)` caller get none. Both DFS walks
(`_collectDesiredDescendants` `tree_sync_controller.dart:730-743`,
`_syncChildrenRecursive` `:764-794`) push children unconditionally with no visited set:
a `childrenOf` cycle (`a → b → a`) loops forever inside `syncRoots`; a DAG (same key
under two parents) walks exponentially before producing last-write-wins thrash that
`syncMultipleChildren` asserts against (S014) but `syncRoots` doesn't.

**Solution.** Add a `seen` set to both walks; on revisit, throw `ArgumentError` naming
the repeated key (message parity with `_normalizeTree`'s cycle error). O(N) memory
already proportional to the walk; negligible cost.

**Dependencies:** none.
**Verification:** unit tests — cycle and DAG inputs throw; deep-chain test still passes
(`tree_sync_deep_tree_test.dart`).

## 2.4 Auto-expand heuristic overrides a user's deliberate collapse of a retained parent

**Category:** bug (UX state loss)

**Issue.** `expandParentsThatGainedChildren`'s `rememberedBeforeSync` filter
(`_sync_helpers.dart:44-56`) only covers keys that were **removed and remembered**. A
parent that stays in the tree the whole time is never in expansion memory: user
collapses P → a filter-sync empties P's children → filter cleared, children return →
heuristic sees "gained first children" + not remembered + not expanded → `expand(P)`,
overriding the user's collapse. Violates the helper's own stated intent ("don't override
a user's deliberate collapse"). Verified by repro during audit.

**Solution.** Remember the parent's expansion state at the moment its child list
transitions non-empty → empty during a sync (in `_syncChildrenImpl`, when the last child
is removed and the parent survives, record `_expansionMemory[parent] =
controller.isExpanded(parent)` — the same memory the restore path already consults).
The heuristic's existing `rememberedBeforeSync` check then naturally skips the
user-collapsed parent, and the sync controller's own `_restoreExpansion` handles the
re-expansion of parents that *were* expanded. This keeps the policy in one place
(expansion memory) instead of adding widget-side "user ever collapsed" tracking.

**Dependencies:** none (coordinates with 2.1/2.2 edits in the same file — land after).
**Verification:** new widget test reproducing the collapse → filter → unfilter sequence,
asserting `isExpanded(P) == false`; existing auto-expand tests
(`synced_sliver_tree_test.dart`) stay green.

## 2.5 `SyncedSliverTree` re-diffs and re-validates the whole tree on every ancestor rebuild

**Category:** perf

**Issue.** `didUpdateWidget` unconditionally runs `_sync(animate: true)`
(`synced_sliver_tree.dart:684-708`). No `identical()` check on the mode inputs
(`_tree`/`_nodeRoots`/`_snapshot`/`_flatItems`), though callers routinely pass the same
collection instance across rebuilds. Per no-op rebuild: two deep copies of the
children-by-parent map (`:711-713`, `:763`), a remembered-keys set copy, full
`TreeSnapshot` reconstruction + `_validate()` for hierarchy/flat modes, a full-tree
`_collectDesiredDescendants` walk, and a per-parent `_syncChildrenImpl` allocating keys
list + two sets + Fenwick even when nothing changed. With a few thousand nodes under a
per-frame-rebuilding ancestor this is O(N) UI-thread work per frame for zero change.

**Solution.** Two independent layers:
1. **Widget-level fast path:** per mode, skip `_sync` when the identity of the mode
   input(s) is unchanged from `oldWidget` (e.g. `identical(oldWidget._tree,
   widget._tree)` for `.tree`; both `_nodeRoots` and `_nodeChildrenOf` for `.nodes`;
   snapshot/list identity for the rest). Duration/curve/indent propagation stays
   unconditional. Document that mutating the same collection instance in place requires
   passing a new instance (standard Flutter convention, same as `ListView.children`).
2. **Sync-level cheap early-out:** at the top of `_syncChildrenImpl`, before any
   allocation, walk `desired` vs the current list once (keys in order + `data`
   equality + no pending-deletion members) and return early on exact match —
   mirroring `TreeController.setChildren`'s C026 fast path. Keep step 7 (deferred
   expansion-restore retry) before the early return.

**Dependencies:** 2.1/2.2 change what "current" is in `_syncChildrenImpl` — land this
after so the early-out compares against controller truth.
**Verification:** extend `rebuild_budget_test.dart` with a no-op-ancestor-rebuild case
asserting zero controller mutations and zero Fenwick allocations (indirectly: no
structural notifications, unchanged `structureGeneration`).

---

# Phase 3 — Reorder layer (`TreeReorderController` / `SliverReorderableTree`)

## 3.1 Pointer → row resolution is off by `precedingScrollExtent`; drop indicator has the mirrored bug

**Category:** bug · **Repro:** `audit_repro_f42_test.dart`

**Issue.** `_pointerToScrollSpaceY` returns `position.pixels + viewportLocal.dy` —
viewport scroll space (`tree_reorder_controller.dart:355-362`) — but
`findRowAtPaintedY` consumes **sliver-local** offsets (first tree row at 0). With any
sliver above the tree the resolved drop target is `precedingScrollExtent` px below the
hovered row. The drop indicator has the mirrored bug: `indicatorScrollY` is built from
sliver-local `paintedOffset` (`:426-445`) while `_DropIndicator` converts with
`indicatorScrollY - scrollable.position.pixels` (`sliver_reorderable_tree.dart:415`) —
also off by `precedingScrollExtent`.

**Solution.** Define the coordinate contract explicitly and convert at both boundaries:
- Pointer: subtract the tree sliver's `constraints.precedingScrollExtent` in
  `_pointerToScrollSpaceY` (session.renderObject is laid out during a drag; guard with
  `renderObject.geometry != null`). The result is genuine sliver-local space for
  `findRowAtPaintedY`.
- Indicator: keep `TreeDropTarget.indicatorScrollY` in **viewport scroll space** (add
  `precedingScrollExtent` when constructing the target in `_resolveZone`), so the
  existing `- position.pixels` consumer math becomes correct. Document both fields'
  spaces on `TreeDropTarget`.

**Dependencies:** none.
**Verification:** promote `audit_repro_f42_test.dart`; add an indicator-position
assertion to the same harness (header + hover row center → indicator at row edge).

## 3.2 Dragged row can be evicted mid-drag: orphaned session + autoscroll ticker running forever

**Category:** bug · **Repro:** `audit_repro_f41_test.dart`

**Issue.** The drag gesture lives on the dragged row's own `GestureDetector`
(`sliver_reorderable_tree.dart:280-307`) and `_ReorderableRowState` has no
deactivate/dispose hook. `RenderSliverTree.isNodeRetained`
(`render_sliver_tree.dart:1157-1194`) has no dragged-row case, so the post-frame
stale-eviction sweep (`sliver_tree_element.dart:379-429`; not gated during drags — no
animations/slides run mid-drag) evicts the source row once autoscroll moves the viewport
far enough. `onLongPressEnd`/`Cancel` then never fire: `endDrag`/`cancelDrag` is never
called, `isDragging` stays true forever, and the autoscroll ticker keeps jumping the
scroll position toward the frozen edge-zone pointer every frame.

**Solution.** Two complementary pieces:
1. **Generic pin API on the render object:** `Set<TKey> _pinnedNodes` with
   `pinNode(TKey)`/`unpinNode(TKey)`; `isNodeRetained` checks it first.
   `TreeReorderController.startDrag` pins the dragged key via
   `session.renderObject`; `endDrag`/`cancelDrag` unpin (in the `finally` introduced by
   3.3); `dispose` unpins any active session's key. Deliberately generic (not
   "draggedKey" plumbing) — keeps the render object ignorant of drag semantics and
   reusable for future retention needs.
2. **Lifecycle backstop in the row widget:** `_ReorderableRowState.deactivate()` — if
   `_isDraggingThisRow` and `reorderController.draggedKey == widget.nodeKey`, call
   `cancelDrag()`. Covers non-eviction unmount paths (node removed mid-drag, tree
   swapped) where ending the session promptly is the correct degraded behavior.

**Dependencies:** none (3.3 builds on the unpin placement).
**Verification:** promote `audit_repro_f41_test.dart` (its assertions are
fix-agnostic across both pieces by design).

## 3.3 `endDrag` commits a stale target with no revalidation and no exception safety; stages the FLIP baseline before validating

**Category:** bug · **Repro:** `audit_repro_f44_test.dart`

**Issue.** `endDrag` (`tree_reorder_controller.dart:258-316`) consumes the target
resolved at the last pointer move. If the tree mutated since (dragged node or target
parent became pending-deletion / was purged — routine with server-driven updates), the
commit throws (`moveNode` StateError, `reorderChildren`/`reorderRoots` ArgumentError);
`_session = null` / `notifyListeners()` sit *after* the mutation with no try/finally, so
the session is permanently stuck, and the exception escapes a `GestureDetector` callback
(the row wrapper's `_endDrag` has no catch). Additionally `beginSlideBaseline` is staged
**before** any validation (`:274-277`) — on the failure path a consumed-by-nobody
baseline is stranded, and first-wins staging (`render_sliver_tree.dart:578-608`) then
blocks every subsequent slide stage until an unrelated layout flushes it.

**Solution.** Restructure `endDrag`:
1. **Re-resolve, then validate, before staging:** call `_recomputeDropTarget()` first
   (cheap; the drop must reflect current truth anyway), then validate the session —
   dragged key live & not pending-deletion; `target != null`; target parent exists, not
   pending-deletion, not self/descendant of dragged. On any failure → `cancelDrag()`
   (which after 3.2 also unpins).
2. Only then `beginSlideBaseline` + commit.
3. Wrap the commit in `try { … } finally { unpin; _session = null;
   notifyListeners(); }` and rethrow — after 1.2 and step 1 the throwing paths should be
   unreachable, so a rethrow is a genuine invariant violation rather than a UX path;
   the finally guarantees the session never sticks either way.

**Dependencies:** 1.2 (removes the index-space ArgumentError source), 3.2 (unpin
placement).
**Verification:** promote `audit_repro_f44_test.dart` (asserts no-throw + session
cleared); re-run `external_cancel_drag_test.dart`, `tree_reorder_controller_test.dart`.

## 3.4 Stale `_isDraggingThisRow` lets a released first finger commit a *different* drag session

**Category:** bug (low)

**Issue.** External `cancelDrag()` (S059 fix) clears state-level UI but not the
row-level `_isDraggingThisRow` flag (`sliver_reorderable_tree.dart:329-350` — only the
row's own `_endDrag`/`_cancelDrag` reset it). `startDrag` silently cancels an existing
session (`tree_reorder_controller.dart:213-215`). Sequence: finger 1 dragging row 1 →
external cancel (or finger 2 long-presses row 2, cancelling session 1) → finger 1
releases → row 1's `_endDrag()` runs `reorderController.endDrag()`, committing **session
2's** target and tearing down its indicator.

**Solution.** Rows verify ownership before forwarding: in `_updateDrag`/`_endDrag`/
`_cancelDrag`, require `reorderController.draggedKey == widget.nodeKey` in addition to
the local flag (clearing the local flag when the check fails). One-line guard per
callback; no controller change.

**Dependencies:** 3.3 (same functions; land after to avoid churn).
**Verification:** new test extending `external_cancel_drag_test.dart`: external cancel →
second session → first gesture ends → session 2 unaffected.

## 3.5 `below`-zone drop on an expanded parent: indicator shows the first-child slot, commit delivers the after-subtree slot

**Category:** bug (UX)

**Issue.** For an expanded target with visible children, `TreeDropZone.below` draws the
indicator directly under the target row (`tree_reorder_controller.dart:433-437`) — the
first child's visual slot — but commits "next sibling of target", potentially many rows
lower. The indicator lies whenever the target is expanded.

**Solution.** Resolve `below` on an **expanded** target with children as first-child
(`parentKey = targetKey, rawIndex = 0` — identical to `into`, which already uses the
same indicator position), preserving current behavior for collapsed/leaf targets. This
matches conventional tree-DnD semantics and makes indicator and commit agree by
construction.

**Dependencies:** none (respects 1.2's live-space contract automatically).
**Verification:** new test: hover below an expanded parent → drop → node lands as first
child; indicator y equals commit slot's y.

---

# Phase 4 — Render layer correctness

## 4.1 Bulk fast path: sticky force-create runs `_recomputeOffsets()` over stale per-nid extents

**Category:** bug (transient geometry corruption)

**Issue.** Documented invariant (`render_sliver_tree.dart:176-179`): under the
bulk-only fast path the per-nid offset/extent arrays are fresh **only for cache-region
nids**. Pass 2's `extentsChanged` handler respects this (`:2024-2038` — materializes the
stale tail, then drops the fast path). The sticky force-create path does not: when a
force-created sticky ancestor's measured extent differs from its (stale) slot,
`totalScrollExtent = _recomputeOffsets()` (`:2136-2146`) walks **all** visible nids
reading stale extents — overwriting correct offsets and the frame's
`geometry.scrollExtent` with garbage, while `_bulkCumulativesValid` stays true.
Trigger: `expandAll` + `maxStickyDepth > 0` + a sticky ancestor outside the cache
region on a non-throttled sticky frame.

**Solution.** Mirror the Pass 2 handler: when `stickyExtentsChanged` under
`_bulkCumulativesValid`, materialize per-nid extents for all visible nids outside the
cache region from `getCurrentExtentNid`, then set `_bulkCumulativesValid = false` for
this frame (next frame rebuilds cumulatives), then run the recompute. Extract the
materialize-then-invalidate block shared with Pass 2 into one helper so the two sites
cannot drift.

**Dependencies:** none.
**Verification:** new test: `expandAll` on a tree with `maxStickyDepth: 1`, sticky
ancestor beyond cache, pump to a non-throttled sticky frame → `geometry.scrollExtent`
matches the sum of current extents (compare against a controller-side sum). Re-run
`sticky_small_tree_max_paint_test.dart`.

## 4.2 `geometry.cacheExtent` over-reported — starves subsequent slivers' cache region

**Category:** bug (RenderSliver protocol)

**Issue.** `cacheExtent: math.min(remainingCacheExtent, totalScrollExtent)`
(`render_sliver_tree.dart:2224`) ignores where the cache region starts. Protocol:
cacheExtent is the cache-region portion this sliver consumes, i.e.
`calculateCacheOffset(constraints, from: 0.0, to: totalScrollExtent)`. Scrolled example:
total 1000, scrollOffset 700, cacheOrigin −250 → correct 550, reported 1000 — the next
sliver gets ~450px less cache than entitled, so its children aren't pre-built (visible
jank crossing the tree/footer boundary).

**Solution.** `cacheExtent: calculateCacheOffset(constraints, from: 0.0, to:
totalScrollExtent)` — the framework helper exists precisely for this.

**Dependencies:** none.
**Verification:** new test: CustomScrollView with tree + trailing sliver; scroll near
the tree's end; assert the trailing sliver's `constraints.remainingCacheExtent` matches
the protocol value (or assert children of the next sliver get built within the cache
region).

## 4.3 Consume-time clip prune strips the EXIT clip of a still-absorbing adjacent exit ghost

**Category:** bug (visual) · **Repro:** `audit_repro_f13_test.dart`

**Issue.** The consume-time lazy-prune of `_phantomClipAnchors`
(`render_sliver_tree.dart:647-652`) removes entries whose **own** slide settled. An
ADJACENT exit ghost has zero own-delta from the start (its baseline already equals the
destination's settled position) while its anchor is still sliding up to absorb it —
Step 0a's prune deliberately keeps such ghosts alive with a dual criterion ("ghost AND
anchor both settled", `:2981-2998`, which also reaps the clip anchor in lockstep). An
unrelated same-frame consume therefore strips the clip while Pass A.5 keeps painting the
ghost → unclipped far overhang for a card taller than the destination header.

**Solution.** Scope the consume-time prune: skip entries whose key is still present in
`_phantomExitGhosts` — their clip lifecycle is owned by
`_pruneSettledPhantomExitGhosts`, which already implements the correct dual-settle
criterion and reaps the clip anchor together with the ghost. Entry-phantom entries (not
in the ghost map) keep the own-slide criterion, which is correct for them.

**Dependencies:** none.
**Verification:** promote `audit_repro_f13_test.dart`; re-run
`adjacent_collapsed_exit_ghost_test.dart`, `entry_phantom_clip_unchanged_test.dart`.

## 4.4 Exit-ghost baseline snapshot disagrees with what Pass A.5 actually paints → t=0 snap on re-move

**Category:** bug (visual) · **Repro:** `audit_repro_f14_test.dart`

**Issue.** `snapshotVisibleOffsets`'s exit-ghost augmentation computes the ghost's
painted position as `anchorPos.y + ghostSlideY` where `anchorPos.y` is the anchor's
**live** position (structural + the anchor's own in-flight slide)
(`render_sliver_tree.dart:1293-1296`). Pass A.5 actually paints at the anchor's
**settled** top (sticky `pinnedY` when pinned, else `layoutOffset` *without* the
anchor's slide) minus the direction-aware tuck, plus the ghost's slide (`:2681-2701` —
with an extensive comment explaining why settled-top is load-bearing). Re-moving a ghost
mid-slide installs the new slide from a baseline that differs from the painted truth by
`anchorSlideDelta + tuck` — a visible snap of exactly that many pixels.

**Solution.** Extract one shared helper —
`double _exitGhostPaintedTopScrollSpace(ghostKey, anchorKey)` — implementing exactly the
Pass A.5 formula in scroll-space (settled anchor top: `pinnedY + scrollOffset` when
sticky-pinned, else `layoutOffset`; minus `_exitTuckFor(ghostNid, anchorKey, slidUp:
_phantomExitSlidUp[ghostKey])`), and use it from **both** Pass A.5 (converting to paint
space) and the snapshot augmentation (adding `ghostSlideY`). Single-source-of-truth by
construction; the existing `ghost_remove_in_flight_test.dart` oracle (which mirrored the
stale formula) must be updated to the paint-truth oracle the repro uses.
**Edge-anchored ghosts** (`_phantomExitEdge` keys) need their own branch in the shared
helper: the snapshot augmentation currently computes *every* ghost anchor-relative
(`:1272-1298`) while Pass A.5's edge fallback paints them at the live viewport edge
(`:2638-2648`) — the same snap class through a different formula. In the helper,
resolve edge ghosts as `viewport.baseForEdge(edge)` (mirroring the paint fallback) so
parity holds for both ghost kinds.

**Dependencies:** 4.3 (same subsystem; 4.3's prune scoping changes which entries
survive to be snapshotted — land 4.3 first so this item's tests run against final prune
behavior).
**Verification:** promote `audit_repro_f14_test.dart`; update + re-run
`ghost_remove_in_flight_test.dart`, `remove_in_flight_continuity_test.dart`.

## 4.5 Exit ghost re-promoted to visibility by a *non-animated* mutation paints twice per frame

**Category:** bug (visual)

**Issue.** The "ghost became visible again" prune runs only inside
`_consumeSlideBaselineIfAny` (`render_sliver_tree.dart:961-982`) — i.e. only when an
animated mutation staged a baseline. A hidden ghost key made visible by a
**non-staging** path (e.g. `expand()` of the collapsed destination parent with
`animationDuration == Duration.zero`, or any mutation while animations are disabled)
sits in `visibleNodes` while still in `_phantomExitGhosts`; if its anchor is still
sliding, Step 0a keeps the entry (dual-settle criterion), Pass A paints the row at
`structural + slideDelta` (no `_phantomExitGhosts` check in the loop, `:2498-2549`) and
Pass A.5 paints the **same RenderBox** again anchor-relative. Two copies for up to a
slide duration; a compositing child (RepaintBoundary in `nodeBuilder`) painted twice in
one frame throws.

**Solution.** Move the re-visible prune from the consume path into Step 0a
(`_pruneSettledPhantomExitGhosts`): before the settle checks, drop entries whose key
`controller.isVisible(key)` — mirroring the consume-time logic (including
`_phantomExitSlidUp`/`_phantomExitEdge` lockstep removal). Step 0a runs every layout,
so every visibility-changing mutation is covered regardless of staging. The consume-time
copy becomes redundant and is removed (single owner).

**Dependencies:** 4.3/4.4 (same function/subsystem — land in this order).
**Verification:** new test: mid-absorption ghost + `expand(destination, animate: false)`
→ assert single paint (paint-purity harness from `paint_purity_test.dart` /
`reparent_painted_coverage_test.dart` oracles).

## 4.6 Empty-tree early return strands a staged FLIP baseline (first-wins blocks all later slides)

**Category:** bug (low)

**Issue.** The empty-visible-order branch (`render_sliver_tree.dart:1685-1692`) returns
before `_consumeSlideBaselineIfAny` and Step 0a/0b pruning. An animated mutation that
stages a baseline and empties the tree leaves the baseline pending; first-wins staging
(`SlideBaselineSlot.stage`) then blocks every later stage, and when the tree repopulates
the stale pre-empty offsets get consumed as the FLIP "before" of an unrelated mutation
(wrong one-frame deltas).

**Solution.** In the empty branch, before returning: discard any pending baseline
(`_composer.baselineSlot.consume()` and drop), clear ghost maps (`_composer.reset()`
level cleanup for ghost/phantom state — reuse the controller-swap reset block), and
reset `_lastObservedScrollOffset`.

**Dependencies:** none.
**Verification:** new test: animated `remove` of the last root → re-add roots with an
animated move → slide installs with correct deltas (no stale baseline).

## 4.7 Hit-test order disagrees with paint z-order during slides; clipped phantom regions stay tappable

**Category:** bug (low, transient)

**Issue.** Paint layers sliding rows above static rows sorted by |delta|, and clips
entry-phantom rows behind their anchors (`render_sliver_tree.dart:2489-2580`,
`:2909-2955`); `hitTestChildren` iterates in structural order with no equivalent
(`:3274-3353`) — during a slide, taps on visually-overlapping rows go to the
structurally-earlier row, and the clipped-away region of an entry-phantom row can steal
taps from the anchor covering it.

**Solution.** Match paint's priority in hit-test Phase 2: when slides are active,
test sliding rows first in **descending** |delta| order (paint's topmost = first hit
priority), then static rows; for keys in `_phantomClipAnchors`, reject hits landing
inside the anchor-occluded region (reuse `_resolvePhantomAnchorBounds` in hit-test
space). Idle frames (no slides) keep today's single loop — zero overhead on the common
path.

**Dependencies:** 5.2 shares the loop (implement together or sequence 5.2 → 4.7).
**Verification:** new test: mid-slide overlapping rows → tap routes to the visually-top
row; entry-phantom overlap region routes to the anchor.

---

# Phase 5 — Performance

## 5.1 Off-cache parentData refresh rebuilds an O(N) cumulative (with allocation) on every layout

**Category:** perf (highest-impact render cost)

**Issue.** The post-sticky refresh block (`render_sliver_tree.dart:2298-2359`) runs
whenever any child is mounted and, on every non-bulk frame, allocates
`Float64List(N+1)` and walks all N visible nodes via `getCurrentExtentNid` — to service
the usually-zero-to-few mounted children outside the cache region. On a 100k-node tree
this is ~800KB allocated and 100k extent-chain resolutions **per scrolled frame**,
defeating the file's own O(viewport) machinery (the block's "Cost is O(_children)"
comment is wrong for the cumulative build). Layout runs on every scroll frame, so this
is the dominant steady-state cost for large trees.

**Solution.** Three cumulative guards (each independently safe):
1. **Lazy build:** construct the cumulative only when the loop actually encounters an
   off-cache, live, visible child (hoist the loop's early `continue`s; on the common
   scroll frame every mounted child is in-cache → zero extra work).
2. **Persistent scratch:** reuse a grow-only `Float64List` buffer instead of allocating.
3. **Freshness invariant (follow-up, biggest win):** analysis shows that in non-bulk
   mode `_nodeOffsetsByNid` is fresh for *all* visible nids after every layout branch
   (full walk on structure change / bulk exit; suffix walk from `firstAnimIdx` with a
   valid stable prefix during animations; equality-walk on transitional frames;
   untouched-but-valid on pure scroll). If that invariant is confirmed by a
   debug-assert soak (add a debug check comparing slot values against a freshly built
   cumulative for one release cycle), the cumulative can be dropped entirely and the
   loop can read `_nodeOffsetsByNid[nid]` — making the whole block O(_children).
   Ship 1+2 immediately; 3 behind the assert soak.

**Dependencies:** none.
**Verification:** `parent_data_refresh_iteration_test.dart` (R124) extended to assert
zero cumulative builds on a pure-scroll frame with all children in-cache; existing
paint/layout suites.

## 5.2 Paint / hit-test / semantics loops never terminate at the viewport end — O(N) hashes per frame and per pointer event

**Category:** perf

**Issue.** Pass A (`render_sliver_tree.dart:2498-2549`), hit-test Phase 2
(`:3274-3353`), and the semantics visitor iterate from the first visible index to the
**end of the tree** — every below-viewport row pays a sticky check, a nid→key
resolution, and a `_children` hash probe per frame (paint) and per pointer event
(hit-test). ~100k wasted hashes per frame near the top of a 100k-row tree.

**Solution.** Bound the iteration end using the same overreach logic as the start:
offsets are monotonic in structural order and painted y = structural ± ≤
`slideOverreach`, so `break` when `_nodeOffsetsByNid[nid] > scrollOffset +
remainingPaintExtent + slideOverreach` (paint) / `> hitOffset + slideOverreach`
(hit-test). **Ghost caveat (load-bearing):** composer edge-ghost rows paint at the
viewport edge regardless of structural position — Pass A already skips them (painted in
Pass A.6, which iterates the small ghost registry), so the paint break is safe; hit-test
substitutes the edge base inline, so add a Phase 2b that tests composer-ghost entries
(few) after the bounded main loop. Semantics: iterate `_children` (bounded by mounted
set) instead of `visibleNodes`.

**Dependencies:** mutual ordering with 4.7 (both reshape the hit-test Phase 2 loop) —
implement together, or 5.2 first then 4.7.
**Verification:** new micro-benchmark-style test asserting iteration counts via a debug
counter (pattern of `debugLastParentDataRefreshIterationCount`); full paint/hit-test
suites.

## 5.3 `getEstimatedExtentNid` does a nid→key→hash→nid round-trip inside O(N) hot loops

**Category:** perf

**Issue.** `tree_controller.dart:849-854` resolves nid→key then calls
`_anim.fullExtentOf(key)`, which hashes the key back to the same nid
(`_animation_coordinator.dart:308-313`) — though the underlying store is already
nid-indexed (`_fullExtentByNid`, `:154`). Its callers are exactly the O(N)-per-frame
paths the API was built for: `_rebuildBulkCumulatives`
(`render_sliver_tree.dart:264-266` — whose comment claims the hash is skipped),
`snapshotSettledVisibleOffsets`, the scroll prefix rebuild
(`_scroll_orchestrator.dart:65`), sticky computer, admission policy. One string hash +
map probe per visible row per bulk frame, for nothing.

**Solution.** Add `double? fullExtentOfNid(int nid)` to `AnimationCoordinator` (direct
`_fullExtentByNid` read with the −1 sentinel fold) and to the `AnimationReader`
interface; rewrite `getEstimatedExtentNid` to use it. Callers unchanged.

**Dependencies:** none.
**Verification:** existing suites (behavior-identical); the concurrent_extents and
bulk-path tests.

## 5.4 Every `remove()` pays an O(N + nidCapacity) full-order sweep — the contiguous fast path is unreachable

**Category:** perf

**Issue.** `_purgeAndRemoveFromOrder` purges (releasing nids) **before** compacting
(`_tree_controller_helpers.dart:397-415`); by compaction time every key reports
`kNotVisible`, so `_removeFromVisibleOrder` always takes the non-contiguous branch —
full-order `removeWhereKeyIn` scan plus `_rebuildVisibleIndex` →
`resetIndexAll` (O(nidCapacity) fill) + full reindex. Removing one leaf from a 10k-row
tree costs a 10k sweep + capacity memset; K removes in one batch cost K sweeps.
`setChildren` already demonstrates the fix pattern (captures indices before purging,
`tree_controller.dart:1846-1897`).

**Solution.** In `_purgeAndRemoveFromOrder`, before Step 2's purge, capture each key's
visible index and detect contiguity (min/max/count — same logic as
`_removeFromVisibleOrder`'s detector). If contiguous: clear the reverse-index slots,
purge, then do a suppressed `removeRange(min, max+1)` + `reindexFrom(min)` —
restoring the O(range + suffix) path for the dominant case (a subtree is contiguous in
the visible order by construction). Non-contiguous or partially-hidden batches keep
today's sweep. The zombie-sweep protocol for *animated* finalization
(`_finalizeAnimation` → deferred batch) is unchanged — it genuinely needs the sweep and
is not the hot path.

**Dependencies:** 1.1 (same function family; land 1.1 first).
**Verification:** `purge_*` tests, `remove_from_order_zombie_leak_test.dart`, fuzz
test; new assertion that a single-leaf remove does not trigger `resetIndexAll`
(debug counter).

## 5.5 `moveNode` validation and staging walk the whole subtree up to 4×

**Category:** perf

**Issue.** The cycle check materializes every descendant —
`_getDescendants(key).contains(newParentKey)` (`tree_controller.dart:2365`) — O(subtree)
time + allocation per move; `tree_reorder_controller.dart:520` already demonstrates the
O(depth) ancestor-walk alternative. Additionally `_flattenSubtree(key, includeRoot:
true)` runs up to twice more (phantom anchors `:2455` / exit anchors `:2561`, affected
keys `:2573`), so a 10k-node subtree move does 3–4 full walks.

**Solution.** (a) Replace the cycle check with an ancestor walk from `newParentKey` via
`_parentKeyOfKey`, throwing when it reaches `key` — O(depth), zero allocation. (b) Hoist
one `_flattenSubtree(key, includeRoot: true)` result and reuse it for whichever of the
phantom-anchor / exit-anchor / affected-keys consumers fire (the moved subtree's
internal structure is invariant across the move, so the three reads are identical;
compute lazily on first need).

**Dependencies:** 1.2 (same function — land after to avoid churn).
**Verification:** existing moveNode suites (`animated_move_to_test.dart`,
`rapid_reparent_*`, deep-tree tests — `moveNode on a 5000-deep chain` already guards
stack behavior).

## 5.6 Animation notification fan-out: K op-group tickers × full listener sweeps with per-sweep list allocation

**Category:** perf

**Issue.** Every `expand`/`collapse` creates its own `AnimationController`+Ticker wired
directly to `AnimationCoordinator.notifyListeners`
(`_operation_group_registry.dart:148-165`); with K concurrent operations plus
standalone/bulk/slide tickers the coordinator fires K+3 sweeps per frame, each
allocating `List.of(_animationListeners)` (`_animation_coordinator.dart:229-235`).
The animated-scroll `follower` compounds this (an O(animating-keys) pass + `jumpTo` per
sweep). Minor adjacent waste: `expand`/`collapse` Path 2 call
`standalone.ensureRunning()` (`tree_controller.dart:2844`, `:2969`) though those paths
create no standalone states — one wasted start/stop frame per operation.

**Solution.** (a) **Per-frame coalescing** in the coordinator: `notifyListeners()`
sets a dirty flag and schedules a single dispatch per frame (microtask when in
transient-callbacks phase — runs after all same-frame ticks, before build/layout;
immediate dispatch otherwise). (b) Replace the defensive copy with a reused growable
snapshot buffer. (c) Gate the Path-2 `ensureRunning()` calls on `_hasAnyStandalone`.
A shared op-group timeline (one ticker, per-group progress offsets) is noted as a
possible deeper follow-up but **not** planned — the coalescing removes the per-frame
multiplier at a fraction of the risk, and per-group controllers carry the
reversal/retiming semantics the code relies on.

**Dependencies:** none. Land before 6.1 (touches coordinator internals).
**Verification:** `independent_timelines_test.dart`, `batch_notification_test.dart`;
new test asserting one listener invocation per frame with 3 concurrent op-groups.

## 5.7 Slide-only ticks promoted to full relayout every frame

**Category:** perf (design-sensitive)

**Issue.** The element marks **layout** dirty on every slide tick
(`sliver_tree_element.dart:267-276`), though slides are paint-only by contract
(`tree_controller.dart:1037-1044`); the comment concedes the paint-only routing was
abandoned solely so ghost cleanup (Step 0a/0b) runs. Cost: a FLIP reorder on a large
tree pays full `performLayout` per frame — amplifying 5.1/5.2.

**Solution.** Restore paint-only routing for slide-only ticks, with layout marked on
(a) the settle transition (`_priorTickHadSlides && !hasSlides` — the frame cleanup
actually needs), and (b) any tick where structural/extent animations are also active
(unchanged). Safety argument (verify during implementation): the build window is
computed at the *install* layout with overreach = max |delta| and only shrinks
thereafter, so no new rows need building mid-slide; scroll during a slide triggers
layout through the viewport anyway (covering `normalizeForViewport`); Step 0a/0b
pruning is needed only at settle or at the next mutation layout — both still occur.

**Dependencies:** Phase 4 ghost items (4.3–4.5) first — they finalize Step 0a/0b
ownership this item's safety argument leans on.
**Verification:** full slide suite (`slide_*`, `rapid_reparent_*`,
`mid_slide_eviction_test.dart`, `reparent_painted_coverage_test.dart` unskipped
portions) plus a frame-cost assertion (no `performLayout` during a pure slide except
install/settle frames — debug counter).

## 5.8 `GhostRegistry` structural-position lookup is an O(N) key-equality scan per ghost per scroll frame

**Category:** perf

**Issue.** `_computeTrueStructuralAt` (`_ghost_registry.dart:159-168`) linearly scans
`visibleNodes` comparing keys; it runs per ghost from `normalizeForViewport`, which
performLayout invokes on every scroll frame while ghosts exist
(`render_sliver_tree.dart:1759-1766`) — G × N key comparisons per scrolled frame during
a slide (the "per consume which is tiny" comment predates the per-scroll call site).

**Solution.** Replace the scan with the controller's O(1) machinery:
`visibleIndexOfNid(nid)` for the index, then an offset read — the registry already
holds the controller back-pointer. For the offset, reuse the render's per-nid offsets
via a callback (the call sites live inside layout where offsets for the relevant rows
are fresh), or sum via the existing scroll prefix (`fullOffsetAt`) when extents are
stable. Choose the callback form: `normalizeForViewport(..., structuralYOf:
(nid) => _nodeOffsetsByNid[nid])` keeps the registry decoupled and exact.

**Dependencies:** 5.1 (offset freshness reasoning shared); Phase 4 ghost items first.
**Verification:** ghost/edge suites (`offscreen_anchor_exit_ghost_test.dart`,
`slide_viewport_clamp_test.dart`).

## 5.9 Per-paint allocations; debug ghost capture active in release builds

**Category:** perf (small)

**Issue.** Pass A.5 constructs a `ViewportSnapshot` inside the per-ghost loop
(`render_sliver_tree.dart:2640`) while A.6 hoists it; `ghosts.keys.toList()` /
`activeKeys.toList()` allocate per paint despite read-only passes (Step 0a/0b guarantee
no concurrent mutation); `debugLastPhantomGhostPaint` is cleared and written with fresh
records per sliding ghost per frame in **release** builds (`:2464`, `:2723-2738` — only
`@visibleForTesting`, not assert-guarded).

**Solution.** Hoist the snapshot; iterate maps directly (document the no-mutation
contract at the pass head); wrap the debug capture in `assert(() { ... return true;
}())` so release builds skip it entirely.

**Dependencies:** Phase 4 ghost items (same code).
**Verification:** paint suites; `paint_purity_test.dart`.

## 5.10 No per-row `RepaintBoundary` support

**Category:** perf (feature)

**Issue.** `ListView`/`SliverList` wrap children in `RepaintBoundary` by default
(`addRepaintBoundaries`); `SliverTree` has no equivalent — every repaint (each slide/
animation frame, each scroll frame) re-records every visible row's display list.

**Solution.** Add `bool addRepaintBoundaries = true` to `SliverTree` (and pass-throughs
on `SyncedSliverTree`/`SliverReorderableTree`), wrapping `nodeBuilder` output in
`RepaintBoundary` inside `SliverTreeElement.createChild`. Default **true** to match
framework convention — the animated-extent clip in `_paintRow` composites fine with a
boundary (verify with the clip tests); rows are translated as whole units, the ideal
boundary case.

**Dependencies:** none.
**Verification:** existing paint/clip suites; golden-free behavior tests pass
unchanged; a raster-cache smoke note in the example app.

## 5.11 Debug builds run O(N + nidCapacity) consistency validation on every incremental mutation

**Category:** perf (developer experience / test-suite time)

**Issue.** `_assertIndexConsistency` (full order walk + full nid-table walk ×2 + all
animation mirrors) fires from every `_updateIndicesFrom` / `_updateIndicesAfterRemove` /
`_rebuildVisibleIndex` (`_tree_controller_helpers.dart:25-53`) — N sequential inserts
are O(N²) in debug; the widget-test suite pays it on every mutation.

**Solution.** Keep an O(changed-range) inline check (order/index agreement for the
touched span); move the full sweep behind an opt-in static debug flag
(`TreeController.debugFullConsistencyChecks`), enabled by the fuzz/purge tests that
exist to exercise it.

**Dependencies:** none.
**Verification:** fuzz + purge tests run with the flag enabled; measure suite time
before/after.

---

# Phase 6 — Architecture, consolidation, docs

## 6.1 Duplicated (and already-diverged) cross-source animation teardown logic; dead drifted copies

**Category:** architecture (latent-bug factory)

**Issue.** The Plan-A refactor left capture/teardown logic live in **two** places with
Dart resolution splitting the call sites: extension copies
(`_tree_controller_animation.dart:55-94` capture, `:267-295` remove) serve unqualified
calls inside the part file; class forwarders (`tree_controller.dart:473-475`) route
class-body calls to the `AnimationCoordinator` copies
(`_animation_coordinator.dart:439-478`, `:484-507`). They have **already diverged**: the
extension's bulk check is `members.contains(key)`; the coordinator's `bulk.isMember`
covers `members ∪ pendingRemoval`. Worse, two copies are dead but look authoritative:
`AnimationCoordinator.cancelAnimationStateForSubtree` (`:521-575`, zero callers) lacks
the `preserveEntering` branch that the live extension version has and that
`move_preserves_entering_test.dart` guards — "finishing the refactor" naively would
silently regress tested behavior. Also dead: `computeStandaloneSpeedMultiplier`
(`_standalone_animator.dart:30-42`); and `defaultExtent = 48.0` exists in three copies
(`tree_controller.dart:701`, `_animation_coordinator.dart:40`,
`_standalone_animator.dart:48`).

**Solution.** Single-source the logic in `AnimationCoordinator`: (1) reconcile the bulk
predicate first (see 6.5 — pick `members ∪ pendingRemoval`, the mirror the render layer
already uses); (2) port any extension-only behavior into the coordinator copy, then
delete the extension copies so all sites route through the forwarders; (3) delete
`AnimationCoordinator.cancelAnimationStateForSubtree` (the live extension version is the
spec — it stays, or is moved wholesale, but there is exactly one); (4) delete the dead
speed-multiplier; (5) single `defaultExtent` constant injected where layering forbids
the import (constructor parameter on the animator/coordinator).

**Dependencies:** ALL correctness items touching these functions land first (1.1, 1.4,
1.6) so fixes are made once on the copies that will survive. This is deliberately the
**last** state-layer change.
**Verification:** whole suite; `move_preserves_entering_test.dart` is the sentinel.

## 6.2 `VisibleOrderBuffer` invariants enforced by convention across files

**Category:** architecture

**Issue.** The buffer exposes raw mutable views (`orderNids`, `indexByNid`,
`setIndexByNid`) and a suppression API documented "Misuse silently corrupts the cache"
(`_visible_order_buffer.dart:90-93`, `:314-329`); the controller writes internals
directly (`_tree_controller_helpers.dart:153-154`, `tree_controller.dart:2829-2839`),
and removal correctness rides on the cross-file "zombie entry" protocol explained only
in a 40-line comment. This seam has already produced shipped bugs (the
zombie-leak/purge regression tests) and 1.1 is another live instance.

**Solution.** After 1.1/5.4 land, narrow the seam: add intention-revealing bulk methods
to the buffer — `removeContiguousRange(min, max)` (clears index slots + range-removes +
reindexes), `purgeCompact(Set keys)` (owns the zombie sweep) — and migrate the
controller's direct-write sites to them. Keep the raw views for **read-only** hot paths
(documented), remove `setIndexByNid` from the public surface (the expand mixed-path
reindex loop moves into a buffer method). Not a rewrite — a surface-tightening pass.

**Dependencies:** 1.1, 5.4 (they change the exact call sites being migrated).
**Verification:** fuzz + purge + zombie suites.

## 6.3 Phantom-exit ghost state is four parallel nullable maps mutated in lockstep at 6+ sites; `detach()` leaks them

**Category:** architecture (+ one lifecycle gap)

**Issue.** `_phantomExitGhosts` / `_phantomExitSlidUp` / `_phantomExitEdge` /
`_phantomClipAnchors` must move in lockstep at the two consume branches, the render-side
fallback, the re-visible prune, Step 0a, and controller swap
(`render_sliver_tree.dart:461-517` declarations; sites at `:848-871`, `:944-957`,
`:961-982`, `:2967-3011`, `:89-92`) — invariants (I-MUTEX, I-AGREE, single-writer) held
together by comments. Concrete gap: `detach()` (`:1494-1513`) resets the composer "as
defense-in-depth" but leaves all four phantom maps populated — the same staleness class
it defends against.

**Solution.** Consolidate into one map:
`Map<TKey, _ExitGhost<TKey>>` where `_ExitGhost` is a small record/class
`{TKey anchor, bool slidUp, ViewportEdge? edge, bool clipped}` (`edge != null` XOR
`clipped` encodes I-MUTEX structurally). All six sites become single-map operations;
`detach()` nulls it alongside the composer reset. Mechanical but broad — do after
Phase 4 (the same sites) so it's a pure refactor on green tests.

**Dependencies:** 4.3–4.5, 5.9.
**Verification:** whole ghost/phantom suite.

## 6.4 Slide completion identity guard cannot detect in-place composition; `_xActiveCount` double-decrement (latent)

**Category:** bug (latent)

**Issue.** `_onSlideTick`'s cleanup guard `_slideByNid[nid] != originalEntry`
(`_slide_animation_engine.dart:434-442`) was written for "listener re-installed a new
slide on the same nid" — but composition **mutates the entry in place**
(`:291-334`), so the guard passes for the exact scenario it targets: a same-tick
composition onto a completed entry would be deleted immediately — the freshly
retargeted slide is silently killed and the row snaps to its structural position.
(`_xActiveCount` stays consistent through this — composition's `hadX`/`newHasX`
transitions pair with the removal decrement — so the damage is visual, not counter
corruption.) Latent today (no synchronous compose from `_onTick`), but the guard is
provably ineffective for its stated purpose.

**Solution.** Add a monotonic `installStamp` to `SlideAnimation`, bumped by install and
by composition; cleanup compares stamps instead of identity. Two lines; removes the
false assumption without changing composition's in-place model.

**Dependencies:** none (independent of 6.1).
**Verification:** unit test simulating compose-during-tick via a listener; slide suite.

## 6.5 Bulk-membership predicate disagrees between key path and nid path (latent)

**Category:** bug (latent)

**Issue.** `getAnimatedExtent(key)` checks `members` only
(`_animation_coordinator.dart:637-641`); `getCurrentExtentNid` uses the nid mirror
covering `members ∪ pendingRemoval` (`:773-780`, `_bulk_animator.dart:150-161`). Every
current population path writes both sets, so it's latent — but nothing enforces
`pendingRemoval ⊆ members`, and a divergence would make the scroll orchestrator compute
offsets that disagree with rendered layout.

**Solution.** Unify on `members ∪ pendingRemoval` (the mirror): route the key path
through `bulk.isMember(key)`. Fold into 6.1's reconciliation (same predicate decision).

**Dependencies:** with 6.1.
**Verification:** existing bulk/extent suites.

## 6.6 `insert`/`insertRoot` data-update branches double-refresh the row

**Category:** perf (small)

**Issue.** The `_hasKey` update branches fire both the node-data channel and a
structural notification for the same key (`tree_controller.dart:1684-1711`,
`:2036-2062`) — two refreshes of one row per update (the batch path documents that
structural subsumes data).

**Solution.** Fire `_notifyStructural(affectedKeys: {key})` only when the branch
actually relocated the node; otherwise the node-data channel alone (matching
`updateNode`'s contract). Leave the pending-deletion-cancel branches untouched (they
have genuinely structural effects).

**Dependencies:** 1.2 (same branches).
**Verification:** `tree_node_builder_targeted_rebuild_test.dart`,
`batch_notification_test.dart`; new assertion counting row rebuilds on a data-only
re-insert.

## 6.7 Documentation refresh + promote all repro tests

**Category:** docs / process

**Issue.** `CLAUDE.md`/`AGENTS.md` describe a `TreeMapView` that no longer exists, omit
the `sectioned_sliver_list` module entirely, and don't mention the internal architecture
(NodeStore, VisibleOrderBuffer, AnimationCoordinator + sub-animators, SlideEngine,
SlideComposer/GhostRegistry, reorder layer) that now carries most of the complexity.
Stale docs actively mislead tooling and contributors.

**Solution.** Rewrite the architecture sections of both files against current reality
(modules, layers bottom-up, the two notification channels, nid/ECS conventions,
live-space index contract from 1.2, coordinate-space contract from 3.1); delete
`TreeMapView` references; document the repro-test methodology. As each phase completes,
move its promoted repros from `plans/audit_repros/` into `test/sliver_tree/` per the
house convention (listed per item above).

**Dependencies:** last (documents the end state).

---

# Explicitly deferred (known, documented limitations — no plan items)

- **Transient mid-slide viewport gaps on long-distance reparents** — the three skipped
  tests in `reparent_painted_coverage_test.dart` (`:217`, `:253`, `:287`). The code
  already documents the accepted fix direction (Option B: per-entry precise union of
  slide-intersecting index ranges, `render_sliver_tree.dart:1782-1791`) and its cost.
  Revisit only if user reports resurface after 5.2/5.7 (which change the same math).
- **Sticky-pinned exit-anchor scenario** (`tall_card_occlusion_zorder_test.dart:240`) —
  established as unconstructable; the skip documents why.
- **O(N-suffix) single insert/remove in `VisibleOrderBuffer`** — inherent to the dense
  typed-array design and the right trade-off for realistic tree sizes (memmove beats
  order-statistic trees' constants); `runBatch` already coalesces bulk mutations into
  one rebuild.

# Suggested implementation waves (risk-balanced)

1. **Wave 1 (state correctness):** 1.1 → 1.2 → 1.3 → 1.4 → 1.5 → 1.6 → 1.7 (each small,
   independently testable, all with repros/tests).
2. **Wave 2 (consumers):** 2.1 → 2.2 → 2.3 → 2.4 · 3.1 → 3.2 → 3.3 → 3.4 → 3.5 · 1.8 →
   1.9 · 1.10 · 1.11.
3. **Wave 3 (render correctness):** 4.1 → 4.2 → 4.3 → 4.4 → 4.5 → 4.6.
4. **Wave 4 (performance):** 5.1 → 5.2 (+4.7) → 5.3 → 5.4 → 5.5 → 5.6 · 2.5 · 5.8 →
   5.9 → 5.7 (last: design-sensitive) · 5.10 · 5.11.
5. **Wave 5 (consolidation):** 6.4 · 6.5+6.1 · 6.2 · 6.3 · 6.6 · 6.7.

Every wave ends with the full suite green plus that wave's promoted repros.

---

# Plan audit record (2026-07-15)

After drafting, this plan was adversarially audited: every `file:line` citation
(~90) was re-opened against the code, each mechanism re-traced, solutions checked for
mutual conflicts, the dependency graph cross-checked against per-item lines, and all
15 repro files verified to exist with matching docblocks. Nine defects were found and
are corrected in the text above:

1. (self-audit) 2.2 originally sourced "current" children from `getChildren` — would
   re-issue `remove()` on exiting rows; corrected to `getLiveChildren`/`liveRootKeys`.
2. (self-audit) 1.6 originally added new nodes to a mid-flight bulk group — they would
   pop to `full × value` on join; corrected to route new nodes through standalone
   animations.
3. 1.3 silently broke `tree_controller_test.dart:1994-1997` (expects
   `AssertionError`); expectation update now called out.
4. 1.9 assumed `TreeController.dispose()` calls `_scroll.dispose()` — it doesn't;
   wiring gap now part of the fix.
5. 1.2 enumerated eight index-conversion sites; there are ten (the two
   pending-relocation different-parent branches were missing).
6. 6.4's secondary claim (`_xActiveCount` underflow) was arithmetically wrong;
   corrected to the real consequence (silently killed composed slide).
7. 1.1 misattributed `_insertNewNodeAmongSiblings` to an inline `insert()` range;
   citations separated.
8. 4.4 left edge-anchored ghosts outside the parity fix; the shared helper now
   explicitly covers the edge-base branch.
9. 5.2 ↔ 4.7 mutual ordering was declared on only one side; both sides and the graph
   note now agree.

No mechanism-level (diagnosis) defect survived the audit; all corrections were in
solution follow-through. Diagnoses of the high-severity items (1.1, 1.2, 1.6, 2.1,
3.2, 4.1, 4.3, 4.4, 5.1) were independently re-verified against source.
