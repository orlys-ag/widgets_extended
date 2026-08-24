# sliver_tree code review, 2026-08-22

Scope: `lib/sliver_tree` (27k lines, 47 files) reviewed for correctness,
architecture and performance at commit `4d15c0c` (0.0.34). Baseline before the
review: `flutter test` = 1070 passed, 4 skipped, 0 failed.

Method. Every file in the module was read in full, either by me or by one of
nine parallel read-only reviewers, each owning one layer. Reviewer output was
treated as a lead, not a finding: every item below that says **confirmed by
test** was reproduced by a probe test I wrote and ran against the unmodified
code in this session (probe sources are summarized in the appendix; they were
not committed). Items marked **confirmed by reading** were traced end to end
in source by me, with the cited lines re-read. Items marked **plausible** have
a complete trace but no repro; they are listed so the fixer can decide, and
their severity is capped at Medium. Three reviewer claims were refuted by
probes and are listed at the end so they are not re-investigated.

Audit verdict. Each finding carries a "Worth fixing" line. The short version:
the six High items are user-visible with common inputs (a tall row, scroll-to-key
after a mutation, `maxDepth`, a `GlobalKey` in a row, a theme toggle) and should
be fixed. Most Medium items are real but need a specific sequence; the Low
section is cleanup and should be batched, not scheduled individually.

Line numbers refer to the files as they exist at `4d15c0c`.

## Audit pass (second pass over this document)

Every item was re-checked; the reading-only and plausible ones were given
probes they did not have the first time. Six corrections resulted, listed here
so a reader of an earlier copy can diff:

- **H2 threshold was wrong.** I wrote "any row taller than the 250 px
  `cacheExtent`". Measured: a 251 px and a 260 px row produce no blank at any
  scroll offset; the effect starts around 300 px and scales with height. The
  first probe's scroll sweep stopped short of the affected window, which is why
  it read as a lower threshold. Corrected in place with the measured numbers.
- **H5 mechanism narrowed and confirmed.** Isolated with three controls: a
  plain `GlobalKey` (no `Form`) is enough, no drag is clean, no key is clean,
  and `showDragProxy: false` is clean. The proxy is the trigger, in the default
  configuration.
- **M15 promoted to High.** The failure is not limited to hoisted subtrees: a
  standard `MaterialApp(theme:)` toggle leaves every row stale, while an
  equivalent `SliverList` updates correctly. The row builder does re-run once,
  but reads the pre-animation value and is never re-run when the theme
  animation lands.
- **M18 withdrawn as a defect.** `showDragProxy`'s doc already states the proxy
  renders outside the row's ancestry, "the same contract as
  `Draggable.feedback`", and directs users to re-provide ancestors via
  `dragProxyBuilder`. Confirmed by test that a local `Theme` is not captured,
  but that is the documented contract, not a bug. Kept as an optional
  improvement in the Low section.
- **M24 refuted.** Probed the exact scenario (one reorderable row among plain
  rows): the row still forms its own semantics node, labelled "B", carrying its
  three custom actions. Moved to the refuted list.
- **M25 promoted from plausible to confirmed**, with a clean A/B: with a
  `ScrollPosition` swap at drag start the drop target freezes while the content
  scrolls 1000 px; without the swap it tracks r5 to r15 to r25.

Two probe defects of my own are worth recording, since both initially produced
a wrong reading: the H2 sweep range (above), and an M25 probe that printed only
`indexInFinalList`, which is 0 for every "into" target and so looked frozen when
it was not. The corrected probe prints `targetKey`, `zone` and `parentKey`.

## Summary

| ID | Sev | Area | Status | One line |
|----|-----|------|--------|----------|
| H1 | High | render/scroll | test | Estimate vs measured height is never corrected: content jumps on scroll-up, `animateScrollToKey` lands 312 px off or 3588 px short |
| H2 | High | render/admission | test | A tall row (about 300 px and up) leaves a blank band in the viewport for the second half of scrolling past it |
| H3 | High | scroll | test | `animateScrollToKey` called after a mutation (before layout) clamps to the pre-layout `maxScrollExtent`, returns true, scrolls nowhere |
| H4 | High | controller | test | `expandAll(maxDepth:)` during an in-flight collapse reverses the collapse of nodes it leaves collapsed: visible rows under a collapsed parent |
| H5 | High | reorder widget | test | A row containing any `GlobalKey` throws on every drag; the proxy mounts the same widget instance twice |
| H6 | High | element | test | Inherited-widget reads in `nodeBuilder` never refresh: a `MaterialApp` theme toggle leaves every row on the old theme (was M15) |
| M1 | Med | controller | test | `insert`/`insertRoot` of a mid-exit node under a collapsed parent leaves a permanent visible row under the collapsed parent |
| M2 | Med | controller | test | Re-inserting a mid-exit node (default flags) keeps its old subtree; `remove(animate:false)` + insert does not |
| M3 | Med | controller | test | `expand(animate: false)` during an in-flight collapse inserts new descendants ahead of still-visible siblings (wrong visible order) |
| M4 | Med | controller | test | With a comparator, re-inserting an existing key moves it one slot right |
| M5 | Med | animation | test | Standalone animations spawned by expand/collapse are timed by the `enterExit` family (orphan row outlives its parent's collapse) |
| M6 | Med | render/perf | test | The bulk-only "O(1) per frame" fast path falls off on every frame (float mismatch), costing O(N) per frame |
| M7 | Med | render | test | Paint-extent loop reads unwritten per-nid slots on bulk frames: `paintExtent` under-reported, trailing sliver painted inside the tree |
| M8 | Med | render/admission | test | Bulk `collapseAll` never admits rows after the collapsing subtree: blank area, then pop at dismiss |
| M9 | Med | controller/perf | test | K inserts under a parent with S siblings cost O(K*S); 8000 appended to 8000 = 14 s |
| M10 | Med | render/ghosts | test | Exit-ghost lifecycle reads the anchor's composed delta: a held make-room preview keeps a settled ghost alive and painted for a whole drag |
| M11 | Med | reorder | test | The hidden dragged row shadows rows the preview shifted into its band: on an upward reversal the gap snaps home and "below b" is unreachable |
| M12 | Med | sync | test | `syncRoots` computes root insert indices before deferred removals, then issues a spurious `reorderRoots` that moves exiting roots to the bottom |
| M13 | Med | sync | test | `syncRoots` lacks the mover-subtree deferral `syncMultipleChildren` got in 0.0.34: a mover under a removed node is purged and re-created |
| M14 | Med | element | test | `forgetChild` drops the render box eagerly; the framework drops it again: assert on `GlobalKey` reparent out of a row (`addRepaintBoundaries: false`) |
| M15 | - | element | test | Promoted to H6 by the audit |
| M16 | Med | controller/element | test | `moveNode` depth change does not dirty mounted rows hidden under a collapsed node in the moved subtree (stale `depth` after re-expand) |
| M17 | Med | reorder widget | test | Drag proxy is sized and positioned in the viewport's cross-axis frame, not the tree sliver's (`SliverPadding` shifts it) |
| M18 | - | reorder widget | test | Withdrawn: proxy theme capture is a documented contract, not a defect. Optional improvement, see L29 |
| M19 | Med | reorder widget | test | Every reorderable row is wrapped in `Opacity(1.0)`: one extra composited layer per row, `addRepaintBoundaries: false` is ineffective, hidden row keeps focus |
| M20 | Med | scroll | test | `animateScrollToKey` alignment ignores the sticky band; alignment 0 lands the target exactly under its pinned header |
| M21 | Med | controller | test | Same-parent relocation via `insertRoot`/`insert` notifies only the moved key; displaced siblings keep stale `indexInParent` |
| M22 | Med | animation | test | `expand` Path 1 detaches the group with a synchronous notify window and never re-bumps the generation: stale animating mirror |
| M23 | Med | animation/perf | test | Empty operation-group shells keep `hasActiveAnimations` true for a full duration |
| M24 | - | reorder widget/a11y | test | Refuted: the row forms its own semantics node with its actions |
| M25 | Med | reorder | test | Scroll subscription bound to the `ScrollPosition` at `startDrag`; a position swap mid-drag freezes the drop target |
| L1..L29 | Low | various | mixed | See the Low section (29 items; L29 is M18's optional improvement, kept after M18 was withdrawn) |

## High

### H1. Scroll position is never corrected for estimate vs measured row height

Status: confirmed by test (three symptoms).

Where: `render_sliver_tree.dart` `performLayout` never sets
`SliverGeometry.scrollOffsetCorrection` (grep over `lib`: 0 hits). Offsets are
a global prefix sum of `getCurrentExtentNid`, which falls back to
`TreeController.defaultExtent` (48) for unmeasured rows
(`tree_controller.dart:981-985`). Pass 2 measures every admitted row,
including rows above the viewport, and on a difference rewrites every later
offset (`render_sliver_tree.dart:2819-2822`, `:2853` `_recomputeOffsetsFrom`).
The immediate scroll path has no post-layout snap
(`_scroll_orchestrator.dart:227-276`); the doc at
`tree_controller.dart:1984-1985` ("the render pass that includes the target
will snap to the exact offset on the next frame") describes code that does not
exist. Reference: `RenderSliverList` emits a correction whenever a leading
child's placement moves (`flutter/packages/flutter/lib/src/rendering/sliver_list.dart:148,158,191`).

What happens (400 roots, 100 px rows, estimate 48):

- Scroll jitter. `jumpTo(8000)`, then scroll up 10 px per step. At the step
  where an above-viewport row enters the cache region and is measured, the
  content moves 102 px for a 50 px scroll. Repeats every 48 px of upward
  scroll, one 52 px jump each.
- `animateScrollToKey("r200", duration: zero)`: r200 is painted at y = 312,
  not y = 0. (Measured: pixels 10536 against the target's offset of 10848 as
  recomputed after the scroll.)
- `animateScrollToKey("r200", duration: 300ms)`: the target is computed once
  from estimates; rows measured during the animation grow the content, and the
  scroll ends at pixels 10536 while r200's offset has become 14124, i.e. 3588 px
  short. The row at the top of the viewport is r146, 54 rows before the target.

Note that the default Material row (`ListTile`, 56 px) is already taller than
the 48 px estimate, so every app with un-estimated rows hits this after the
first far jump.

Worth fixing: yes. This is the sliver protocol's core invariant for
variable-height content and the README advertises variable-height rows.

Fix: in Pass 2, for admitted rows with index below
`_findFirstVisibleIndex(scrollOffset)` whose stored extent was the unmeasured
fallback (`getMeasuredExtent(key) == null` before `_layoutNodeChild`) and that
are not animating, accumulate `actual - estimated`; if non-zero, set
`geometry = SliverGeometry(scrollOffsetCorrection: delta)` and return (the
viewport re-runs layout, `viewport.dart` `layoutChildSequence`). Exclude
animating rows or every expand above the viewport would be "corrected". For
the animated scroll, route through the existing
`_animatedConcurrentScroll` follower (which re-derives the target per tick)
whenever the target lies in an unmeasured region, or add a final snap to the
immediate path as the animated-concurrent path already has.

### H2. Admission starves the viewport below a row taller than the cache extent

Status: confirmed by test.

Where: `_layout_admission_policy.dart:66-67` (accumulators start at 0 at
`cacheStartIndex`), `:78` (`budgetCap = remainingCacheExtent + 2*overreach`),
`:85-94` (break when both budgets fail), `:119-125` (a non-animating row
charges its whole extent). `cacheStartIndex` is the row CONTAINING the cache
start (`render_sliver_tree.dart:2733`, `_findFirstVisibleIndex`), so a tall
leading row is charged in full even though most of it lies above the cache
window. The bulk path anchors `fullCacheEnd` at the first row's top
(`render_sliver_tree.dart:2745-2749`), same flaw.

What happens: rows of 48 px except r1, which is tall. Sweeping every scroll
offset in r1's span (default 600 px viewport, 250 px `cacheExtent`), the worst
case per height is:

| r1 height | rows in viewport with no render box | blank px | at scroll |
|-----------|-------------------------------------|----------|-----------|
| 200 | 0 | 0 | - |
| 251 | 0 | 0 | - |
| 260 | 0 | 0 | - |
| 300 | 1 | 31 | 595 |
| 400 | 3 | 127 | 695 |
| 700 | 9 | 415 | 995 |

A uniform-height list of 700 px rows shows the same defect (one missing row);
a uniform list of 56 px rows never does.

The affected window is the second half of scrolling past the tall row: the
blank appears once the cache start is more than about 250 px into the row and
grows until the row leaves the cache region, so it spans roughly
`height - 250` px of scrolling and peaks just before it clears. In other words
the row is still charged its full height against the budget when only its last
sliver is still relevant.

Threshold note (corrected during the audit): the effect is not simply
`height > cacheExtent`. 251 px and 260 px rows produce nothing measurable;
it becomes observable around 300 px and the blank band is roughly
`height - 270` px. The exact constant follows from the budget formula
(`remainingCacheExtent + 2 * overreach`) and therefore scales with the
viewport's `cacheExtent`.

Worth fixing: yes. Expanded cards, images and media rows routinely exceed
300 px, and the symptom is a blank viewport region with no error. Below about
300 px nothing is observable, so short-row trees are unaffected.

Fix: seed both accumulators with the part of the first row that lies before
the cache start (`nodeOffsetsByNid[first] - effectiveCacheStart`, a negative
number) instead of 0, and in `_admitBulkFastPath` derive `fullCacheEnd` from
the full-space cache start rather than `fullStart`. Independently, never let
the budget refuse a non-animating row whose live offset is inside the paint
region. Promote the probe as a regression test.

### H3. `animateScrollToKey` after a mutation clamps to the pre-layout `maxScrollExtent`

Status: confirmed by test.

Where: `_scroll_orchestrator.dart:236-276`. The one-frame wait at `:245-252`
runs only when the orchestrator itself expanded an ancestor
(`collapsedAncestors.isNotEmpty && expandedCount > 0`); the clamp at
`:265-268` reads `position.maxScrollExtent` with no other guard.
`expand()` marks the node expanded before its group starts
(`tree_controller.dart:3725`), so a caller-side expand makes
`collapsedAncestors` empty and skips the wait.

What happens: 10 roots x 50 px (tree shorter than the 600 px viewport,
`maxScrollExtent == 0`), k9 collapsed with 30 children.
`controller.expand(key: "k9"); animateScrollToKey("k9c29", ...)`: offset
1892 is clamped to 0, `animateTo(0)`, future resolves `true`, pixels stay at
0 while `maxScrollExtent` grows to 1356 over the next frames; the target is
never shown. Same result with `TreeAnimationStyle.disabled` after 35
`insertRoot` calls followed by a synchronous scroll (no layout has run yet).
This is the most common reveal pattern in apps.

Worth fixing: yes.

Fix: in the plain path, if `SchedulerBinding.instance.hasScheduledFrame`
(a layout is pending) await `endOfFrame` before reading the position, as
`:245-252` already does; if `_controller.hasActiveAnimations` is true, route
through `_animatedConcurrentScroll` with an empty ancestor list and let its
loop also wait on `!hasActiveAnimations` (the follower already re-derives the
target per tick). Pin with the scenario above.

### H4. Depth-limited `expandAll` reverses collapses of nodes it leaves collapsed

Status: confirmed by test (op-group and bulk variants).

Where: `tree_controller.dart:4096-4099` (a node joins `nodesToExpand` only
when `withinDepthLimit`), `:4128-4147` (children are harvested into
`nodesToReverseExit` "regardless of depth"), `:4186-4203` (every op group
with `pendingRemoval` is un-pended and `forward()`ed with no check that its
operation key was re-expanded; `group.pendingRemoval.clear()` at `:4192`),
`:4208-4231` (`_clearBulkPending()` at `:4212` un-pends every bulk member
likewise). The `completed` handler removes nothing from the order
(`_tree_controller_animation.dart:266-282`).

What happens: `a > b > c` all expanded. `collapse(key: "b")` animated, then
mid-flight `expandAll(maxDepth: 1)`. After settle: `isExpanded("b") == false`
and `visibleNodes == [a, b, c]`. `collapse("b")` is now a no-op (guard at
`tree_controller.dart:3919`), so the user cannot hide `c`; the next order rebuild drops `c`
without animation. Bulk variant (`collapseAll()` then `expandAll(maxDepth: 1)`)
produces the same zombie row.

**A second `maxDepth` defect, in the opposite direction** (found while drafting
the fix, confirmed by test): `collapseAll(maxDepth: 0, animate: false)` is
semantically a no-op, since `withinDepthLimit` is `depth < maxDepth` and no
node has depth below 0. But the collection loop that fills `nodesToHide`
(`tree_controller.dart:4318-4323`) never consults `maxDepth` at all: it walks
every expanded root and harvests its visible descendants, while
`_collapseAllInRegistry(maxDepth)` correctly clears no expansion flag. The
non-animated arm then removes every harvested row from the visible order.
Measured on roots `r > [a, b]` with `r` expanded:
`collapseAll(maxDepth: 0, animate: false)` yields `isExpanded("r") == true`
with `visibleNodes == ["r"]`. The tree renders collapsed while its expansion
state says expanded, and nothing restores the rows until an unrelated full
order rebuild. Same root cause as the item above (a `maxDepth`-gated mutator
whose row collection is not `maxDepth`-gated), so it is fixed alongside it.

Worth fixing: yes. `maxDepth` is public API, and the state it leaves behind
cannot be repaired from the public surface short of a structural rebuild.

Fix: in both reversal branches, un-pend only members whose post-flip ancestor
chain is expanded (`_ancestorsExpandedFast`); members whose chain stays
collapsed keep exiting (move them to a standalone exit, which captures the
current extent). Gate the depth-independent `nodesToReverseExit` harvest on
the child's parent being in `nodesToExpand` or already expanded.

### H5. A `GlobalKey` inside a row breaks dragging

Status: confirmed by test, isolated with three controls.

Where: `sliver_reorderable_tree.dart:1381` hands the exact widget instance
the `nodeBuilder` returned to `_onDragStart` (`:670`); `:1559-1560` the proxy
mounts that same instance as its content while the in-place copy stays
mounted at opacity 0 (`:1127-1130`, deliberately, to preserve State).
Framework: `framework.dart` `_retakeInactiveElement` pulls a `GlobalKey`'d
element out of its current parent when the same key is inflated elsewhere.
Reference: `reorderable_list.dart:1140-1144` replaces the in-place item with a
`SizedBox` while the proxy shows the child, so the key moves and is never
duplicated.

What happens: any `GlobalKey` in the row subtree is enough (the audit used a
bare `SizedBox(key: GlobalKey())`; a `Form` is not required). On the first drag
frame: "A RenderPointerListener was mutated in RenderSliverTree.performLayout
... when none of its ancestors is actively performing layout", followed by
null-check errors on the move and release frames.

Controls, all in the default configuration (`showDragProxy: true`,
`addRepaintBoundaries: true`):

| case | result |
|------|--------|
| `GlobalKey` row, drag | exceptions |
| `GlobalKey` row, no drag | clean |
| no `GlobalKey`, drag | clean |
| `GlobalKey` row, drag, `showDragProxy: false` | clean |

So the trigger is precisely the proxy mounting the row's captured widget
instance while the in-place copy is still mounted.

Worth fixing: yes. `Form`/`TextFormField` keys and anchor keys for
`showMenu` are common in editable rows, and the failure is an exception on
every drag rather than a visual glitch.

Fix: either stop mounting the captured instance twice (render the in-place
row as a sized placeholder while hidden, the reference approach; trades away
the preserve-State choice), or keep the design and make the hazard explicit
(document on `showDragProxy`/`dragProxyBuilder` that keyed rows must supply a
`dragProxyBuilder` that does not mount `rowChild`, plus a debug assert for a
top-level `GlobalKey`). Add a test: keyed row, drag, `takeException()` null,
same `State` after drop.

### H6. Inherited-widget reads in `nodeBuilder` never refresh rows (was M15)

Status: confirmed by test, including the standard `MaterialApp` theme toggle,
with a `SliverList` control.

Where: `sliver_tree_element.dart:538` passes the element itself as the row
builder's `BuildContext`, so a `Theme.of(context)` inside a `nodeBuilder`
registers the dependency on `SliverTreeElement`. `:194-201` `performRebuild`
only calls super and queues nothing: its comment claims reconciliation lands on
the next layout, but `_dirtyKeys` is untouched and no layout is marked.
Reference: `SliverMultiBoxAdaptorElement.performRebuild` re-runs `updateChild`
for every child, which is why the same code works inside a
`SliverChildBuilderDelegate`.

What happens, measured with a builder-run counter:

| step | builder runs | value the builder saw | painted |
|------|--------------|-----------------------|---------|
| initial (light) | 1 | light | light |
| after `theme: ThemeData.dark()` | 2 (+1) | light | light |
| after an unrelated `updateNode` | 3 (+1) | dark | dark |

The row builder does re-run once when the toggle rebuilds the widget, but at
that moment `MaterialApp`'s `AnimatedTheme` is still on the old value. The
theme then animates over `kThemeAnimationDuration`, and every tick of that
animation DOES notify this element: `_InheritedTheme.updateShouldNotify` is
`theme.data != old.theme.data` (`material/theme.dart:231`), and the element is
a dependent because the row builder called `Theme.of` with its context. What
fails is the handling, not the delivery: each notification marks the element
dirty, `performRebuild` runs, and it queues nothing, so no row is ever
rebuilt again. The row stays on the pre-animation theme until something else
dirties it. The same widget tree built on a `SliverList` updates correctly,
so this is specific to this element.

(An earlier draft of this paragraph said the theme "animates without
rebuilding the subtree", which is true of the SUBTREE but wrong about the
dependent: the notification arrives and is dropped. The distinction matters
because it rules out "notify harder" as a fix and points at `performRebuild`.)

Worth fixing: yes, and higher than I first graded it. `Theme.of` /
`MediaQuery.of` / `DefaultTextStyle.of` inside a row builder is ordinary usage,
and "toggle dark mode, the list keeps the old colors until you scroll" is a
visible, reproducible defect in the default configuration.

Fix: in `performRebuild`, after `super.performRebuild()`, queue
`_dirtyKeys.addAll(_children.keys)` and `markNeedsLayout()` (the same lazy
refresh `update` performs at `:190-191`); move the queueing there so `update`
does not do it twice. Regression test: the theme-toggle table above.

## Medium

### M1. `insert`/`insertRoot` of a mid-exit node under a collapsed parent leaves a permanent visible row

Status: confirmed by test.

Where: `tree_controller.dart:2884-2951` (`insert` pending-deletion branch:
relocation, `_cancelDeletion`, `_markVisibleOrderDirty`);
`_tree_controller_animation.dart:405-413` (`_cancelDeletion` always reverses
the root key into an ENTER; only descendants get the ancestor-visibility
policy at `:478-484`); `tree_controller.dart:4627-4636` (the rebuild keeps a
collapsed parent's children that carry a standalone state);
`_tree_controller_animation.dart:668-678` (a completed enter returns false,
so the row is never removed from the order).

What happens: `P1 (expanded) > X`, `P2 (collapsed) > Y`. `remove(key: "X")`
animated, then `insert(parentKey: "P2", node: X)`. After settle:
`visibleNodes == [P1, P2, X]` with `isExpanded("P2") == false`, permanently.
`test/sliver_tree/tree_controller_test.dart:1377-1419` runs this sequence but
asserts only parent/children/depth. `moveNode(animate: true)` handles the
same situation correctly through its case-2 policy.

Worth fixing: yes; the declarative layer reaches the same `_cancelDeletion`
for a same-parent re-add when the parent was collapsed after the removal
started (`tree_sync_controller.dart:659-665`).

Fix: route the root key through the same `_ancestorsExpandedFast` policy as
descendants: hidden chain means clear pending-deletion and let the exit run
(or `_removeAnimation`), no enter. Extend the existing test with
`expect(controller.visibleNodes, ["a", "b"])`.

### M2. Re-inserting a mid-exit node keeps its old subtree

Status: confirmed by test.

Where: `tree_controller.dart:2398-2470` (`insertRoot` pending branch),
`tree_controller.dart:2851-2945` (`insert`),
`_tree_controller_animation.dart:400-425`
(`_cancelDeletion`), `:470-490` (case 2 clears pending-deletion on
descendants so `_finalizeAnimation` takes the non-purge branch).

What happens: `A > a1` expanded; `remove(key: "A", animate: true)`;
`insertRoot(TreeNode(key: "A"))` with default flags. Immediately
`getChildren("A") == [a1]`, `hasChildren("A") == true`; after the exit
settles a1 is hidden but structurally present, and `expand("A")` brings it
back. The same sequence with `remove(animate: false)` yields no children, so
the result depends on whether an exit animation was in flight.

Worth fixing: yes, but decide the contract first. The preserved descendants
are a visual-smoothness choice (see `skip_repro_test.dart:205-260`); the
structural leftover is not documented anywhere on `insertRoot`/`insert`.
Either keep descendants pending-deletion so the existing purge machinery
removes them at exit end (visual smoothness kept, structure consistent with
the non-animated path), or document that re-adding a mid-exit node restores
its subtree.

### M3. `expand(animate: false)` mid-collapse misorders new descendants

Status: confirmed by test.

Where: `tree_controller.dart:3726-3745`: the non-animated branch collects
every descendant not in the order and inserts them as ONE block at
`parentIndex + 1`, regardless of their structural position relative to
descendants still in the order (mid-collapse op-group members). The animated
paths handle this (`:3798-3799` `_insertNewNodeAmongSiblings`; `:3866-3892`
cursor tracking).

What happens: `A > [a1, a2]` expanded; `collapse("A")` animated;
`insert(parentKey: "A", node: a3)`; `expand("A", animate: false)`. Visible
order becomes `[A, a3, a1, a2]` against structure `[a1, a2, a3]`, and stays
that way until an unrelated full rebuild. `ensureAncestorsExpanded`
(`_scroll_orchestrator.dart:179`) calls `expand(animate: false)`, so
`animateScrollToKey` in immediate mode can trigger it. The debug consistency
checks only compare order against reverse index, not against structure.

Worth fixing: yes (narrow trigger, silent corruption).

Fix: in the `!animate` branch, when any member of `nodesToShow` is already in
the order, call `_markVisibleOrderDirty()` instead of the block insert (or
reuse the Path-2 cursor). Consider an order-equals-structural-DFS assertion
under `debugFullConsistencyChecks`.

### M4. Comparator re-insert of an existing key moves it one slot right

Status: confirmed by test.

Where: `tree_controller.dart:2487` (`setData` before the search),
`:2504-2505` (`_sortedIndex(_roots, node)` with the node still in the list),
`:2515-2529` (`wantsRelocate`, `removeAt(current)`, `insert(sortedDesired)`);
identical copy for children at `:2979-3003`. `_sortedIndex` is an upper-bound
search (`:2328-2329`), so the node's own slot compares equal and returns
`current + 1`, which is not adjusted after the removal.

What happens: comparator on data; roots `[a:Apple, b:Banana, c:Cherry]`;
`insertRoot(TreeNode(key: "b", data: "Banana"))` gives `rootKeys == [a, c, b]`.
A second identical call flips it back. Each call fires a structural
notification and a full order rebuild for what should be a no-op.

Worth fixing: yes (sort invariant broken by an idempotent call).

Fix: compute the sorted position with the node excluded (or subtract 1 when
`sortedDesired > current`), and treat "already at the sorted position" as a
data-only update. Share the block between `insertRoot` and `insert`.

### M5. Standalone animations spawned by expand/collapse are timed by the `enterExit` family

Status: confirmed by test.

Where: the standalone ticker reads only `_enterExitDurationGetter()` /
`_enterExitCurveGetter()` (`_standalone_animator.dart:225, 258`);
`AnimationState` (`types.dart:52-100`) carries no per-state spec. Ten of the
thirteen `_startStandalone*` call sites sit inside `expandCollapse`-gated
mutators (`tree_controller.dart:3793, 3800, 4007, 4217, 4246, 4257, 4273,
4432, 4461, 4481`); only `:2580, 3074, 3117` are insert/remove.
`animation_style.dart:10-11` documents `enterExit` as the insert/remove
family. This violates the "declare the family once at the boundary" rule in
CLAUDE.md.

What happens (`expandCollapse: 300ms`, `enterExit: 10s`): `expand(P)`
animated; at 100 ms `expand(C1)` animated; at 150 ms `collapse(P)` (Path 1).
`G1` (C1's child) gets a standalone exit. At +310 ms `visibleNodes == [P, G1]`:
C1 and C2 are gone with P's group, G1 lingers as an orphan row under the
collapsed P for about a second. With `enterExit: Duration.zero` G1 would
vanish instantly while its siblings animate.

Worth fixing: yes, but it is invisible under the uniform default style. Fix
when touching the animation layer.

Fix: resolve the spec at the install boundary (add duration/curve to
`AnimationState` or to `_startStandaloneEnter/ExitAnimation`), pass
`effectiveEnterExit` from insert/remove/`_cancelDeletion` and
`expandCollapse` from the expand/collapse family, and advance each state by
its own duration. Add a family-flow test for the nested case.

### M6. The bulk-only fast path falls off on every frame

Status: confirmed by test (numeric probe plus timing).

Where: `render_sliver_tree.dart:455-456` writes the per-row estimate as
`_offsetAtVisibleIndex(i + 1) - offset`; `:2402-2405` measures
`getAnimatedExtent` = `fullExtent * value`
(`_animation_coordinator.dart:722-724`); `:2819` compares with exact `!=`.
On mismatch: `_materializeBulkStaleExtents` (O(N)), `_recomputeOffsetsFrom`
(O(N)), `_bulkCumulativesValid = false`, and the next frame
`_rebuildBulkCumulatives` (O(N)) again.

Evidence: a Dart script mirroring the two formulas finds a mismatch among the
first 18 admitted rows on 17 of 17 frames of a linear 300 ms animation and
189 of 200 random values. Timing: 30 bulk frames cost 62 ms at 5k rows and
349 ms at 400k rows (about 24 ns per row per frame of O(N) work). The fast
path's documented purpose ("turns the O(N)-per-frame Pass 1 walk into O(1)",
`:221-229`) does not hold.

Worth fixing: yes for large trees; the work is a cheap typed-array pass, so
at 10k rows it is well under a millisecond per frame. Land together with M7.

Fix: compare with a tolerance (`precisionErrorTolerance`) or compute the
estimate with the same arithmetic as the measurement (`full * value` for
members, `full` otherwise).

### M7. Paint-extent loop reads unwritten per-nid slots on bulk frames

Status: confirmed by test (narrow: only on frames that stay on the fast path,
which M6 currently makes rare).

Where: `render_sliver_tree.dart:3035-3051` reads `_nodeOffsetsByNid` /
`_nodeExtentsByNid` directly instead of `_structuralOffsetAt` (`:311-315`);
under the fast path only admitted nids are fresh (`:232-236`). Unwritten
slots read 0/0, which never triggers the loop's `break`, so the loop is also
O(N) on those frames.

What happens: 2000 children, `expandAll()`, a frame at value 0.5 exactly
(a 150 ms gap after the first frame): `geometry.paintExtent == 480` against
600 expected, and a trailing `SliverToBoxAdapter` footer is painted at
y = 480, inside the tree, for that frame. `hitTestExtent` follows
`paintExtent`, so taps below 480 are rejected.

Worth fixing: yes, it is a two-line change and becomes every-frame once M6 is
fixed.

Fix: use `_structuralOffsetAt(i, nid)` and the next offset for the extent in
that loop, or replace the loop with
`calculatePaintOffset(constraints, from: 0, to: totalScrollExtent)` (rows are
contiguous, so the intersection equals the sum).

### M8. Bulk `collapseAll` admission never admits rows after the collapsing subtree

Status: confirmed by test.

Where: `_admitBulkFastPath` breaks on `fullOffset >= fullCacheEnd`
(`render_sliver_tree.dart:457-459`), a FULL-space position that is constant
for the whole animation. The op-group path has a post-animation view that
charges exits 0 (`_layout_admission_policy.dart:48-52, 117`); the bulk path
has no equivalent.

What happens: `A (50 expanded children), B, C`, 48 px rows, `collapseAll()`.
At value 0.17 (250 ms into 300): B's animated offset is 448 (inside the
600 px viewport), B and C are not mounted, `debugChildCount == 18`. The lower
viewport is blank until the non-bulk settle layout mounts them in one pop.
The same defect was fixed for the op-group path in a prior cycle
(`sliver_tree_widget_test.dart:884`, "collapsing a subtree pre-mounts
following rows so they do not pop in at dismiss"); nothing pins the bulk
path.

Worth fixing: yes.

Fix: give `_admitBulkFastPath` a post-space bound too: admit while
`fullOffset < fullCacheEnd` OR
`stableCumulative[i] - stableCumulative[cacheStartIndex] < remainingCacheExtent`.

### M9. K inserts under one parent cost O(K * S)

Status: confirmed by measurement.

Where: `tree_controller.dart:2281-2291` `_siblingRefreshSet` builds a Set of
every sibling plus the parent on every `insert`/`remove`/`moveNode`/reorder
(`:2594, :3080, :3137, :3222, :3314, :3636-3637`); inside `runBatch` the union
`addAll` at `:2300` repeats the O(S) work per call.

Evidence (animations disabled): batch-inserting N children under a parent
that already has N: N = 2000 takes 445 ms, N = 8000 takes 13.9 s (31x for 4x
N). Under a collapsed parent (no visible-order work at all): 271 ms vs
5.1 s. `TreeSyncController.syncChildren` appending N to N: 252 ms vs 5.1 s.
The batch-exit `affectedKeys` set had 16001 entries.

Worth fixing: yes for any list that grows incrementally past a few thousand
rows.

Fix: inside a batch, record the dirty parent (or "the sibling list of X
changed") and materialize the sibling set once at batch exit; or switch to
`affectedKeys: null` (full refresh) when S exceeds the mounted count, since
the element only rebuilds mounted rows anyway
(`sliver_tree_element.dart:245-249`).

### M10. Exit-ghost lifecycle reads the anchor's composed delta

Status: confirmed by test (lifecycle half); painted-overlap half traced only.

Where: prune criterion `render_sliver_tree.dart:3871-3884` (`anchorDy` via
`getSlideDeltaNid`, composed); Pass A.5 paint gate `:3512-3520` (same
composed read); ghost painted base is the anchor's unshifted `layoutOffset`
(`:1696-1698`) while the EXIT clip band uses the anchor's composed painted
position (`:3975-3982`). `getSlideDeltaNid` is FLIP plus preview
(`tree_controller.dart:1032-1041`). The edge-ghost registry was migrated to
FLIP-only reads for exactly this bug class (`_ghost_registry.dart:110-132`,
`ghost_prune_flip_only_test.dart`); the `_ExitGhost` records were not.
CLAUDE.md's "nine FLIP-only read sites" inventory is accurate; the gap is
that these sites are not among them.

What happens: `moveNode(C, into collapsed Q, animate: true)` (exit ghost
anchored on Q), then `setReorderPreviewAtIndex` that shifts Q by +40. After
C's FLIP settles: `debugPhantomExitGhostCount` stays 1,
`isNodeRetained("C")` stays true, for as long as the preview is held. By the
cited geometry the ghost paints at Q's unshifted top with a clip computed from
Q's shifted band, so part of C (a row that should be hidden inside Q) shows
in the gap; I did not pixel-verify that half.

Worth fixing: yes; drag-started-mid-FLIP is a supported state
(`tree_controller.dart:1369-1372`).

Fix: gate prune and paint on `getFlipSlideDeltaNid` for ghost and anchor, and
make the ghost base follow the anchor's HELD (preview) displacement but not
its decaying FLIP: `layoutOffset + (getSlideDeltaNid(anchor) -
getFlipSlideDeltaNid(anchor))` at `:1696-1698`, with the same term added at
the consume-time destinations (`:1115, :1218`). Update the CLAUDE.md count.

### M11. The hidden dragged row shadows rows the preview shifted into its band

Status: confirmed by test.

Where: the dragged rows `[draggedIndex, draggedEnd)` get no preview shift
while rows after them get `-lift` (`tree_controller.dart:1764-1778`), so with
the gap below the dragged block the next rows paint over the dragged block's
band. The dragged row is hidden (opacity 0, `sliver_reorderable_tree.dart:1127-1130`)
but still laid out. Both `findRowAtPaintedY` scans walk visible-index order
and skip only pending-deletion rows (`render_sliver_tree.dart:1990-2014`,
`:2064-2084`), so the lower-index hidden dragged row wins over the shifted
row painted at the same y.

What happens (roots a b c d, 50 px, touch-first): long-press a, move to
y = 145 (target "below c", b paints at 0..50). Move up to y = 40 (visually
b's lower half): the resolver reports index 0 zone `below` (the
current-position target), the gap snaps home (b back at 50), and release
commits `[a, b, c, d]`. "Below b" is unreachable on the way up; it only
appears after the gap closes and the pointer goes down again.

Worth fixing: yes; it is the core drag interaction.

Fix: skip the dragged visible range in the row lookup while a preview is
held. The controller already knows `draggedNid` and the range at
`setReorderPreviewAtIndex`; expose an O(1) "hidden for hit lookup" predicate
from the preview engine and have both scans skip it the way they skip
pending-deletion rows. `ReorderRenderPort` stays unchanged.

### M12. `syncRoots` computes root insert indices before deferred removals

Status: confirmed by test.

Where: `tree_sync_controller.dart:244-257` (root removal deferred to step
2'), `:266-274` (`remaining` built from current roots minus `toRemove`),
`:284-300` (`targetIndex = remainingBit.prefixSum(p)` passed to
`insertRoot(index:)`), `:401-420` (removal after insertion), `:435-453` (step
6 reorder). `_liveIndexToFullInsertIndex` counts every non-pending root
(`tree_controller.dart:2617-2637`), so the not-yet-removed roots shift the
index; `reorderRoots` rebuilds `_roots` as ordered keys plus pending roots
(`:3207-3210`). The children path removes first, then inserts, and does not
have this mismatch.

What happens: roots `[X, A]`, desired `[A, N]`, animated. Result
`rootKeys == visibleNodes == [A, N, X]` with X pending deletion: the exiting
root is moved from the top to the bottom for its whole exit animation, A
slides up, N enters mid-list, and a FLIP baseline is staged for a reorder the
desired list never asked for. `tree_sync_controller_test.dart:1398-1443`
asserts only post-settle order.

Worth fixing: yes (visible animation artifact on the most common
declarative operation, a removal plus an append).

Fix: remove roots whose subtree holds no desired descendant BEFORE step 3,
deferring only roots whose subtree intersects `desiredDescendants`
(matching the children path), so the step-6 reorder becomes a no-op for pure
insert/remove syncs.

### M13. `syncRoots` lacks the mover-subtree deferral

Status: confirmed by test.

Where: the deferral at `tree_sync_controller.dart:613-620` is gated on
`_deferredSubtreeRemovals` and `_moverAncestors`, which only
`syncMultipleChildren` sets (`:106-131`); `_syncRootsImpl` step 5 sets only
`_globallyDesiredChildren` (`:358-369`), so an intermediate removed node hits
`remove(key, animate)` at `:621-622`. 0.0.34 fixed exactly this for
`syncMultipleChildren` ("destroyed a mover's subtree").

What happens (`TreeAnimationStyle.disabled`, `expansionMemory: 0`): current
`A > [B > [x > [y]], C], Q`; desired `A > [C], Q > [x > [y]]`. After the
sync x has a new nid (re-created), `isExpanded("x") == false` although x was
never removed from the desired tree, only moved. With animations on and B
visible, `moveNode` revives the pending subtree and the outcome differs, so
it is animation-dependent in the way the 0.0.34 changelog entry describes.

Worth fixing: yes; factor the deferral setup into one helper both entry
points call so they cannot diverge again.

### M14. `forgetChild` drops the render box, then the framework drops it again

Status: confirmed by test.

Where: `sliver_tree_element.dart:589-604` calls
`renderObject.removeChild(box, nodeId)` inside `forgetChild`, justified by
the comment "forgetChild bypasses removeRenderObjectChild". In the framework
in use, `_retakeInactiveElement` calls `parent.forgetChild(element)` and then
`parent.deactivateChild(element)`, whose `detachRenderObject` reaches
`removeRenderObjectChild` -> `removeChild` -> `dropChild` a second time.
Reference: `SliverMultiBoxAdaptorElement.forgetChild` only removes the map
entry.

What happens: `addRepaintBoundaries: false`, a row whose root widget has a
`GlobalKey`; the app builds that keyed widget elsewhere. Debug: `'child._parent
== this'` assertion in `RenderObject.dropChild` (`object.dart:2193`). Release:
null check on `parentData`.

Worth fixing: yes, small and the comment's premise is false for the current
framework. Delete the render-side removal; `insertChild`'s defensive
`dropChild(existing)` (`render_sliver_tree.dart:2150-2152`) already covers
the zombie case the comment worried about.

### M15. Promoted to H6 by the audit

See H6. The audit showed the failure is not limited to hoisted subtrees: a
plain `MaterialApp(theme:)` toggle reproduces it.

### M16. `moveNode` depth change does not dirty mounted rows hidden under a collapsed node

Status: confirmed by test.

Where: `tree_controller.dart:3627-3633` adds `movedSubtree()` (expansion-gated
flatten, `_tree_controller_helpers.dart:265-306`) when the depth changed; the
comment claims expanded rows are the only ones that can be mounted. But
`removeChild` is a no-op in the element (`sliver_tree_element.dart:552-555`)
and eviction is post-frame, so rows collapsed earlier in the same handler are
still mounted; `createChild` never rebuilds a non-dirty mounted row
(`:528-531`).

What happens: `P (depth 0) > C` mounted; in one handler `collapse(P);
moveNode(P, Q); expand(Q); expand(P)`. `getDepth("C") == 2` while the mounted
row still renders its depth-1 label (`parentData.indent` is refreshed to
depth 2, so the row is positioned at depth 2 with depth-1 content).

Worth fixing: yes, cheap. Use the full structural subtree (`getDescendants`,
as `expand` already does at `:3705-3711`) when the depth changed; the element
filters to mounted keys anyway.

### M17. Drag proxy is sized and positioned in the viewport's frame, not the sliver's

Status: confirmed by test.

Where: `sliver_reorderable_tree.dart:1640-1660` (`viewport =
scrollable.context.findRenderObject()`, `left: viewportGlobalLeft`,
`width: viewport.size.width`); rows are laid out at
`constraints.crossAxisExtent - indent` (`render_sliver_tree.dart:2388`) and
`SliverPadding` reduces the child's cross extent and offsets it. The x-depth
hint consumes `PointerSample.sliverX`, which is the scrollable's local x
(`_drag_session.dart:87-89`), not the sliver's.

What happens: `SliverPadding(horizontal: 100)` around the tree. The row is
painted at x 100..700; the lifted proxy's text is at x 0..800. The settle
glide and the depth hint use the same wrong frame (not probed).

Worth fixing: yes; `SliverPadding` around a list sliver is standard layout.

Fix: expose cross-axis geometry (global left, `crossAxisExtent`) on
`ReorderRenderPort` from the `RenderSliverTree` the row already locates, and
subtract the sliver's cross paint offset when computing `sliverX`.

### M18. Withdrawn: proxy theme capture is documented behavior

Status: behavior confirmed by test, but it is the documented contract, so this
is not a defect. Moved to L29 as an optional improvement.

The behavior is real: with the tree under `Theme(data: ThemeData.dark())`
inside a light `MaterialApp`, the in-place row renders "a-dark" while the
proxy renders "a-light" simultaneously. With a local `DefaultTextStyle`
(30 px green), the proxy's text resolves to the framework's no-`Material`
fallback (48 px red) while the row keeps 30 px green.

Why it is not a finding: `showDragProxy`'s doc
(`sliver_reorderable_tree.dart:203-209`) states that the preview "renders in
the root [Overlay], OUTSIDE the row's original ancestry, the same contract as
`Draggable.feedback`", that rows depending on inherited ancestors "need a
[dragProxyBuilder] that re-provides those ancestors", and that the package is
widgets-layer-only and cannot supply `Material` itself. The reviewer's
comparison was to `ReorderableList`, which captures themes; this package
deliberately follows the `Draggable` convention and says so.

### M19. `Opacity(1.0)` around every reorderable row

Status: confirmed by test (both halves). With two rows mounted there are two
`RenderOpacity` objects and both report `isRepaintBoundary == true`, with
`addRepaintBoundaries` set to true AND to false. Focusing a `TextField` in a
row and then dragging that row leaves `focusNode.hasFocus == true` on the
hidden copy.

Where: `sliver_reorderable_tree.dart:1127-1130` wraps
every row, hidden or not, in `Opacity(opacity: hidden ? 0.0 : 1.0)`.
`RenderOpacity.isRepaintBoundary => alwaysNeedsCompositing => child != null
&& _alpha > 0` (`proxy_box.dart:884-887`), so every visible row is a
composited repaint boundary with its own `OpacityLayer` in addition to the
package's `RepaintBoundary` (`sliver_tree_element.dart:540`). With
`addRepaintBoundaries: false` rows are still boundaries through
`RenderOpacity`, so the option changes nothing. No `ExcludeFocus` on the
hidden row, so a focused `TextField` inside the dragged row keeps receiving
keystrokes while invisible.

Worth fixing: yes. Replace with `Visibility(visible: !hidden, maintainSize:
true, maintainState: true, maintainAnimation: true)`: same shape stability,
pointer exclusion and semantics drop, no layer, and `ExcludeFocus` comes with
it. Eight tests introspect `Opacity` for the hidden-state probe and need
updating.

### M20. `animateScrollToKey` ignores the sticky band

Status: confirmed by test (the first probe clamped at the max extent and was
inconclusive; the audit re-ran it with 6 sections of 20 children).

Where: no sticky term anywhere in `_scroll_orchestrator.dart:261-264, 377-380,
459-462`; headers pin at `stackTop` and paint over rows
(`_sticky_header_computer.dart:336, 444-451`,
`render_sliver_tree.dart:3718-3745`).

What happens: `maxStickyDepth: 1`, `animateScrollToKey("r3c10")` with the
default alignment 0. Measured: the target row is painted at `top = 0.0` and
the sticky set is `[r3 @ pinnedY 0.0, extent 48]`, i.e. the 48 px header covers
the 48 px target exactly. The caller cannot compensate, because the pinned
extent depends on which ancestors fall within `maxStickyDepth` and on their
measured heights.

Worth fixing: yes, as an API addition (a `topInset`/sticky-aware option)
rather than a silent behavior change.

### M21. Same-parent relocation notifies only the moved key

Status: confirmed by test. `tree_controller.dart:2536` and `:3010`
(`_notifyStructural(affectedKeys: {node.key})` after `removeAt`/`insert` on
the sibling list) while every other sibling-list mutator uses
`_siblingRefreshSet` (`:2594, :3080, :3137, :3222, :3314, :3636-3637`); the
rationale is at `:2268-2280`. Probe: roots `[a, b, c]`, `insertRoot(c,
index: 0)` gives `affectedKeys == {c}`; a and b keep stale
`indexInParent`/`isFirst`/`isLast` until an unrelated refresh.

Worth fixing: yes, two one-line changes.

### M22. `expand` Path 1 leaves the animating mirror stale when a synchronous listener reads it

Status: confirmed by test (with a listener that reads
`currentlyAnimatingKeys`, which the scroll orchestrator's follower is).

Where: `tree_controller.dart:3765-3782`: `_bumpAnimGen()` at `:3767` runs
BEFORE `runWithGroupDetached` (`:3779`) and nothing bumps after reattach;
collapse Path 1 bumps after (`:3999`). `AnimationController.value=` notifies
synchronously, the coordinator dispatches synchronously outside transient
callbacks (`_animation_coordinator.dart:298-313`), and the mirror rebuild
iterates `opGroups.groups` (`:769-853`), which excludes the detached group,
then caches at the current generation.

What happens: `collapse(A)` animated, then `expand(A)` animated (Path 1):
`isAnimating("a1") == false` while `hasActiveAnimations == true`, and
`computeFirstAnimatingVisibleIndex()` equals the order length, so the render's
active-animation branch recomputes no extents: the reversal appears frozen
until `completed` bumps the generation.

Worth fixing: yes, one `_bumpAnimGen()` after `runWithGroupDetached`.

### M23. Empty operation-group shells keep `hasActiveAnimations` true

Status: confirmed by test. `remove(C, animate)` with `enterExit: 100ms`, then
`collapse(P)` with `expandCollapse: 1000ms`: at 150 ms
`hasActiveAnimations == true` with `currentlyAnimatingKeys == {}` and it
stays true until 1000 ms. Where: collapse Path 2 installs and `reverse()`s
the group even when the member loop skipped everything
(`tree_controller.dart:4017-4039`; expand Path 2 `:3812-3900` likewise);
`_purgeNodeData` removes members without `disposeIfEmpty`
(`_tree_controller_helpers.dart:320-331`) although `removeFromAllSources`
does (`_animation_coordinator.dart:613-636`). Downstream the shell disables
the render cache, runs the per-frame extent walk, and defers stale eviction
(`sliver_tree_element.dart:463, 476`).

Worth fixing: yes (cheap): dispose/skip the group when `members` is empty
after the loop, and call `disposeIfEmpty` from `_purgeNodeData`.

### M24. Refuted by the audit: reorder semantics do form their own node

Status: refuted. The probe built exactly the scenario the reviewer described,
`canReorder: (k) => k == "b"` over rows a, b, c, and walked the semantics tree:
the node carrying the custom actions has label "B" (its own label alone, not a
merge of A/B/C) and carries all three actions, out of 9 nodes total. The
predicted merge into the scroll view's node does not happen, so
`container: true` would change nothing here. No action.

### M25. Scroll subscription bound to the `ScrollPosition` at `startDrag`

Status: confirmed by test (A/B), promoted from plausible by the audit.

Where: `tree_reorder_controller.dart:375` subscribes `scrollable.position`
directly. This is also the only scrollable access outside `PointerSpace`, which
CLAUDE.md names as the sole component allowed to touch the scrollable.
`ScrollableState` swaps its position when the physics runtimeType changes,
which the textbook `physics: isDragging ? NeverScrollableScrollPhysics() : ...`
pattern does on the first drag notification.

What happens: grab r0, hold the pointer at y = 275 (mid-viewport, outside the
autoscroll edge zone) and scroll the list externally underneath it.

| case | position swapped | target at y=275 | after jumpTo(500) | after jumpTo(1000) |
|------|------------------|-----------------|-------------------|--------------------|
| stable physics | no | into r5 | into r15 | into r25 |
| physics flipped on drag start | yes | into r5 | into r5 | into r5 |

With the swap the drop target freezes on the row it first resolved and never
tracks the content again, so the gap shown to the user and the slot committed
on release belong to a position the pointer is no longer over. Autoscroll
drives the same `ScrollPosition`, so it is affected identically.

Worth fixing: yes. Re-validate `identical(_scrollable.position, subscribed)`
inside `PointerSpace.sample()` (the single per-event and per-tick site) and
re-subscribe on change, which also moves the last stray scrollable access
behind `PointerSpace` as the architecture doc requires.

## Low

Batch these; none justifies its own change on its own.

- L1. `remove()` of a node not in the visible order still runs
  `purgeCompact` plus a full reverse-index reset
  (`_tree_controller_helpers.dart:403-421, 481-483`,
  `_visible_order_buffer.dart:507-511`). Probe: `debugOrderResetIndexAllCount`
  +1 per hidden-leaf removal, O(nidCapacity) each. Skip step 3 when the
  pre-purge capture found no visible slot.
- L2. `remaining.insert(targetIndex, ...)` at `tree_sync_controller.dart:319`
  and `:697` is dead O(N) work per inserted key; the list is never read after
  the loop, contradicting the Fenwick rationale at `:259-262`. Delete both.
- L3. `setChildren` is the only mutator that reads `_order` without
  `_ensureVisibleOrder()` (`tree_controller.dart:2690-2850`), and it hand-rolls
  the removal protocols the buffer documents as its own
  (`_visible_order_buffer.dart:145-150`; `removeRange`/`removeWhereKeyIn` have
  no other callers). Probed inside a batch after `moveNode` with full
  consistency checks: no crash, correct by virtue of the batch-exit rebuild.
  Hygiene only.
- L4. Release-mode guard gaps: `updateNode`, `insert`, `setChildren` and
  `moveNode` validate key existence with `assert` only
  (`tree_controller.dart:2691, 2861, 3148, 3368`), and `insert` of an
  existing key overwrites data before `moveNode` can throw (`:2960-2972`).
  `NodeStore.setParent` then null-derefs (`_node_store.dart:278`) after the
  node was adopted, leaving a registered zombie. `setChildren` and
  `reorder*` already throw in all modes; make these consistent.
- L5. `animateSlideFromOffsets` with a key present in both maps but not
  registered throws a null check (`_slide_animation_engine.dart:281, 307,
  597`). Probed. Resolve the nid before `_setSlide` and skip.
- L6. `applyPaintTransform` has no branch for anchor-based exit ghosts
  (`render_sliver_tree.dart:4349-4420` vs Pass A.5 paint at `:3530-3537`), so
  `localToGlobal` on a row disappearing into a collapsed parent reports its
  old slot for the slide's duration. Reading.
- L7. Pass A skips a registry edge-ghost row on the COMPOSED delta
  (`:3417-3421`) while Pass A.6 paints on the FLIP-only delta (`:3658-3661`,
  documented as a pair with `pruneSettled`): a FLIP-settled ghost with a
  held preview offset is painted by neither pass until the next layout.
  Plausible, not probed. Make Pass A's skip ask the FLIP-only question.
- L8. `snapshotSettledVisibleOffsets()` is computed on every baseline consume
  (`:1063`) although only the exit-phantom branches read it (`:1115, :1218`):
  a third O(N) map per animated reorder. Make it lazy.
- L9. `ReorderPreviewEngine.maxAbsDelta` walks every entry per call
  (`_reorder_preview_engine.dart:122-133`) and is read several times per
  frame during a drag; entries span the shifted span (whole list for a
  top-to-bottom drag). All targets share `|target| == lift`, so a high-water
  mark is O(1). Cheap today (linear typed walk), listed for completeness.
- L10. Dead members with no callers (each appears only at its declaration):
  `NodeStore.rawDataAtNid`, `rawDataLength`, `nidOfOrSentinel`,
  `expandedByNid`/`ancestorsExpandedByNid` getters,
  `VisibleOrderBuffer.resizeIndex`, `clearIndexByNid`, `nidAt`,
  `NodeIdRegistry.freeSlotCount`. `rawDataAtNid`'s doc claims the consistency
  check uses it; it does not (`_node_store.dart:236-243` vs `:477-488`).
- L11. Internal contracts on the public surface: the barrel exports
  `SliverTreeElement` and `TreeChildManager`; `RenderSliverTree.childManager`
  is a public mutable field; `admittedSlideBound` is exported while documented
  as internal. Drop the two exports (nothing outside `lib/sliver_tree` uses
  them).
- L12. `insertRoot`/`insert` forward their `enterExit`-gated `animate` into
  `moveNode`'s `reorderSlide` decision (`tree_controller.dart:2404-2406,
  2498, 2858-2860, 2972`): with `enterExit: zero` and `reorderSlide: 300ms`,
  `insert(existing)` slides while `moveNode` would not. The comment at
  `:2490-2493` about `affectedKeys` omitting the moved key is also stale
  (`:3637` includes it).
- L13. Plain-path scrolls do not cancel an in-flight animated-concurrent
  scroll (`_scroll_orchestrator.dart:236-276` never consults
  `_activeScroll`); the follower's `jumpTo` disposes the later
  `DrivenScrollActivity`, whose future resolves `true` early. Confirmed by
  test: an animated-mode scroll to a deep key, then 100 ms later a plain
  `animateScrollToKey("k1")` whose target is 50; both futures return `true`
  and the viewport ends at 2400, the first scroll's destination. The loser
  reports success.
- L14. Expansion memory on the direct `syncChildren` path: the pending re-add
  branch (`tree_sync_controller.dart:652-665`) never consumes the entry and
  `_pruneExpansionMemory` runs only from `_syncRootsImpl` (`:461-464`), so a
  stale `true` can later re-expand a user-collapsed parent. Plausible; items
  under `SectionedListController` are leaves so it is not hit there.
- L15. The gained-children heuristic can override a collapse performed while
  the last child is animating out (`snapshotChildPresence` treats pending
  children as absent, `:922-933`). Plausible, narrow window.
- L16. `syncMultipleChildren` validates per-list duplicates lazily
  (`:798-835`): a bad k-th list leaves earlier parents mutated. Validate all
  lists before the loop.
- L17. `startDrag` does not re-check `_session` after `cancelDrag()`
  (`tree_reorder_controller.dart:295-298`); a listener that starts a drag
  from the cancel notification gets its session overwritten without
  `detachAll` (pin, scroll listener and ticker leak). Reading; custom
  consumers only.
- L18. `startDrag` accepts a pending-deletion or unknown key (`:281-307`;
  `_canCommit` refuses at commit, `:654-656`). Confirmed by test on the
  programmatic path: `startDrag` on a mid-exit key returns `true` and
  `isDragging` becomes true, and the later `endDrag` leaves the order
  unchanged. The pointer path cannot reach it (hit-testing skips exiting
  rows), so this is API-surface only. Return false up front as `moveTo` does.
- L19. `_applyMove` returns the unclamped index on the cross-parent path
  (`:716-719`) against its own contract (`:667-670`). Contrived trigger.
- L20. The autoscroll ticker keeps scheduling frames while parked at a
  scroll extent with nothing to scroll (`_drag_session_behaviors.dart:125-142`
  stops only at zero velocity); `EdgeDraggingAutoScroller` stops. Reading.
- L21. A drag started on a sticky-pinned header probes the content beneath
  the strip (`_drag_session.dart:144-146` claims otherwise;
  `findRowAtPaintedY` does not know pinned bands). Plausible.
- L22. `DropSettler` cancel/fallback glide passes structural positions as
  `current` (`_drag_session_behaviors.dart:484-499`), so an in-flight FLIP on
  the re-grabbed row is double-counted at t = 0 (`_slide_animation_engine.dart:288`).
  Plausible; needs a probe.
- L23. Sticky-classified rows never show a FLIP slide (Pass A skips sticky
  rows before reading deltas, `render_sliver_tree.dart:3384-3386`; Pass B
  paints at `pinnedY`). Design gap; document or exclude a sliding candidate
  from the sticky set for the frame.
- L24. Pass A.7 repaints an exit-ghost anchor a second time per frame
  (`:3677-3717`); with `RepaintBoundary` rows the second `paintChild` moves
  the child's layer, discarding Pass A's X-slide offset, and hit-testing does
  not mirror the new z-order. Plausible; the EXIT clip already excludes the
  band, so A.7 may only be needed for edge-painted ghosts.
- L25. Minor perf: no-op `ClipRectLayer` per sticky header per frame
  (`:3753-3759`); `_paintRow` has no top-edge cull so above-viewport rows in
  the overreach window are composited (`:3780-3782`); the sticky
  subtree-bottom fallback walks the whole visible subtree per layout during
  any animation (`_sticky_header_computer.dart:508-527`); the admission walk
  does not terminate on a run of exits (`_layout_admission_policy.dart:85-94`);
  `getCurrentExtentNid` hashes the key twice per row per op-group frame
  (`_animation_coordinator.dart:874-885`); Pass 2 hashes keys where nids are at
  hand (`render_sliver_tree.dart:2383-2412, 2798, 2817, 2825`);
  `insertAllKeys` bumps each key's ancestor chain instead of one chain bump
  (`_visible_order_buffer.dart:473-477`); `purgeCompact` and `_purgeNodeData`
  clear reverse-index slots that are immediately reset anyway
  (`_visible_order_buffer.dart:533-535`, `_tree_controller_helpers.dart:350`);
  `_propagateAncestorsExpandedToDescendants` allocates two worklists for
  every leaf inserted under a collapsed parent (`_node_store.dart:387-393`).
- L26. Housekeeping that the house rules forbid: three string literals carry
  an em-dash (`animation_style.dart:193`, `render_sliver_tree.dart:876`,
  `sliver_reorderable_tree.dart:735`), and 17 of the module's files contain
  non-ASCII characters (mostly the box-drawing section separators in
  comments). `OverlayEntry` is removed but never disposed
  (`sliver_reorderable_tree.dart:625-626`; the reference calls `dispose()`).
  Doc drift: CLAUDE.md line 94 refers to a `SliverReorderableTree` `wrap`
  callback that does not exist (rows are wrapped unconditionally,
  `sliver_reorderable_tree.dart:752-762`); the `forgetChild` and
  `performRebuild` comments in `sliver_tree_element.dart:197-200, 593-597`
  describe behavior that does not occur (M14, M15); the `setChildren` doc at
  `tree_controller.dart:2690-2693` says old children are purged, which the
  exact-match fast path deliberately does not do; the comment at
  `tree_reorder_controller.dart:550-553` cites a "disabled clear-all" in the
  slide engine that re-bases rather than clears. `_rebaselineUntouched`'s
  rationale (`_slide_animation_engine.dart:645-650`) cannot occur; its only
  effect is restarting un-preserved direct installs' clocks on unrelated
  batches (the cancel glide decelerates under repeated sync moves).
  `TreeController<TKey, ...>` accepts a nullable key type, and a `null` key
  collides with the registry's free-slot sentinel
  (`_node_id_registry.dart:32-34`); bound `TKey extends Object` or assert.
- L27. Bulk reversals re-target op-group envelopes without the Path-1 rebase
  (`tree_controller.dart:4194-4202, 4405-4410`) and the bulk reverse branch
  lets genuinely new nodes join a mid-flight group (`:4223-4227`), both of
  which the neighbouring continuation branches avoid on purpose. Plausible
  one-frame pops.
- L28. Direction flip under a same-frame pending baseline drops the
  edge-to-edge composition (`render_sliver_tree.dart:2574-2580`,
  `_ghost_registry.dart:460-482`), so the ghost pops from one viewport edge to
  the other. Reading; rare (animated move plus a viewport-sized jump in one
  frame).
- L29. Optional (was M18): capture `InheritedTheme` for the drag proxy. The
  current behavior, the proxy resolving `Theme`/`DefaultTextStyle` against the
  overlay, is the documented `Draggable.feedback` contract, so this is a
  convenience improvement rather than a fix: one
  `InheritedTheme.capture(from: rowContext, to: overlay.context)` per session
  would let the default proxy look right without a custom `dragProxyBuilder`.
  Weigh it against the doc's explicit "this package is widgets-layer-only"
  position, which the capture would not change (a `Material` ancestor would
  still be the app's job).

## Examined and not worth fixing, or refuted

- The full-extent admission charge that leaves the lower viewport unbuilt
  during the first half of a large expand is a documented trade-off
  (mass-mount cap); the blank consequence is not documented anywhere. Worth
  a sentence on `LayoutAdmissionPolicy` and in the README, not a change.
- Exit-phantom ghosts are painted but not hit-tested; exiting sticky headers
  are painted but not hit-tested. Consistent with "exiting rows receive no
  interaction".
- Reviewer claim, refuted by probe: a deliberate collapse is lost across
  remove -> childless re-add -> children arrive via `SyncedSliverTree`. The
  probe kept the collapse in both the childless and the with-children
  variants.
- Reviewer claim, not reproduced: a mounted but non-admitted row whose
  content calls `setState` during an expand stays dirty and trips the
  framework's relayout-boundary assert. The probe's paragraph was laid out
  and no assertion fired across three bumps.
- Reviewer claim, refuted for the pointer path: dragging a mid-exit row. Hit
  testing skips exiting rows, so the handle never receives the pointer (see
  L18 for the programmatic case).
- Refuted by the audit (was M24): reorder semantics actions merging into the
  scroll view's node when only one row is reorderable. The row forms its own
  node with its own label and all three actions.
- Withdrawn by the audit (was M18): the drag proxy not capturing inherited
  themes. Real, but the documented `Draggable.feedback` contract. Kept as the
  optional L29.
- Rows between about 250 px and 300 px tall: no measurable admission blank
  (H2's threshold), so the earlier "any row over `cacheExtent`" phrasing
  overstated the reach.
- The live-space index contract, `runBatch` deferral, notification
  coalescing, nid recycling and lockstep growth, the zombie-compaction
  protocol, the slide engine's settle protocol and `installStamp` guard, the
  nine FLIP-only read sites, the bounded drop-target scan, paint/hit-test
  z-order mirroring, drop-zone boundaries and the same-parent downward
  off-by-one, the commit script's validation and teardown, and the deferred
  sync gate were all traced and found consistent with their documentation.

## Appendix: probe notes

All probes used `testWidgets` with `tester` as the `TickerProvider`, the
`MaterialApp > Scaffold > CustomScrollView` harness from the existing widget
tests, and `SizedBox` rows of a fixed height. The sequences that matter are
reproduced in each finding; a few harness details:

- H1: `jumpTo(8000)` on 400 roots of 100 px, then `jumpTo` in 10 px steps
  reading `tester.getRect(find.text(key)).top` of the row returned by
  `findRowAtPaintedY(pixels)`; `animateScrollToKey` variants with
  `Duration.zero` and 300 ms, asserting the target's painted top is 0.
- H2: per scroll offset, every key whose settled span intersects the
  viewport must satisfy `tree.getChildForNode(key) != null`.
- H5 / M11 / M17: `tester.startGesture`, `pump(kLongPressTimeout + 50ms)`,
  `gesture.moveTo`, as in `test/sliver_tree/make_room_preview_test.dart:179-181`.
- M6: Dart script mirroring `_rebuildBulkCumulatives` and
  `_offsetAtVisibleIndex`, comparing `cum[i+1] - cum[i]` with `48.0 * v`;
  timings via `Stopwatch` around 30 `tester.pump(17ms)` calls after
  `expandAll` on 5k and 400k children with a 3 s `expandCollapse` spec.
- M9: `runBatch` of N `insert` calls under a parent with N children,
  animations disabled, N = 2000 and 8000.
- M10: `moveNode(C, "Q", animate: true)` with Q collapsed, one 50 ms frame,
  then `setReorderPreviewAtIndex(draggedKey: "D", gapVisibleIndex: 1)`, two
  400 ms frames, read `debugPhantomExitGhostCount` and `isNodeRetained("C")`.
- M22: `addAnimationListener(() => controller.currentlyAnimatingKeys)`
  before the `collapse`/`expand` pair, then `isAnimating("a1")`.

Audit-pass probes:

- H2: sweep every scroll offset in the tall row's span (`300` to `298 + height`
  in 5 px steps), counting rows whose settled span intersects the viewport but
  have no render box, and summing their on-screen px.
- H5: the same drag with four variants (key/no key, drag/no drag, proxy on/off).
- H6: a builder-run counter plus the value the builder saw, across a
  `StatefulBuilder`-driven `MaterialApp(theme:)` toggle, with the equivalent
  `SliverList` as a control.
- M19: `tester.renderObjectList<RenderOpacity>(find.byType(Opacity))` and
  `isRepaintBoundary` per row for both `addRepaintBoundaries` values; a
  `FocusNode` per row, focused before the drag.
- M20: 6 sections of 20 children, `maxStickyDepth: 1`, compare the target's
  painted top against `debugStickyHeaders`.
- M24: walk `pipelineOwner.semanticsOwner.rootSemanticsNode` collecting the
  node whose `customSemanticsActionIds` is non-empty, then read its label.
- M25: hold the pointer mid-viewport (outside the edge zone) and drive the
  scroll externally with `jumpTo`, printing `targetKey`/`zone`/`parentKey`,
  with and without a physics-driven position swap.
- L13: overlapping animated and plain `animateScrollToKey` calls, comparing
  both futures and the final pixels against each target.

Per the house repro-test convention, each confirmed item should be promoted
to a `test/sliver_tree/` regression test asserting the correct behavior
before its fix lands.
