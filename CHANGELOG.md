## 0.0.36

- Board 2D-scrollable.
- Added `BoardDragConfig.dragProxyOpacity` and
`BoardDragConfig.draggedItemOpacity`, the opacity of the drag proxy and of
the item left behind in the lattice while a MOVE session holds it. They
default to 1.0 and 0.5, which changes how a move looks: the proxy was
hardcoded at 0.85 and is now opaque, with the fade moved to the item that
stays put. A resize session fades nothing whatever `draggedItemOpacity`
holds, because it paints no proxy and a faded item would leave nothing at
full strength.
- Added `BoardDragController.movedItem`, a `ValueListenable<TKey?>` holding
the key a live move session holds and null otherwise. It is written at the
two session edges only, unlike the controller's own `ChangeNotifier`, which
fires per pointer move, so an item-level listener can afford it. An app
giving the item left behind a treatment of its own watches this rather than
`BoardItemView.isDragging`, which is false in the lattice build and
documented as such: that item comes from the viewport's delegate, and a
session edge fires no structural notification, so nothing rebuilds it
between the lift and the commit.
- Fix: a sticky header retiring by push-up painted above the tree sliver's own
paint origin, with no clip. In a tree short enough to fit its viewport the
sliver declares no visual overflow, so the viewport pushes no clip either and
the header was drawn over whatever sat above the scroll view; with a sliver
above the tree it was drawn over that sliver even when the viewport did clip.
The header is now clipped to the sliver's paint region at the top as it already
was at the bottom. The 0.0.35 no-clip fast path is unchanged for settled
headers; the clip appears only while a header slides up out of the band.

## 0.0.35

- **BREAKING** `AnimationState` gains a required `family` field
(`TreeAnimationFamily`, newly exported): the animation family whose style
spec times the state, declared at the install site. External constructions
of `AnimationState` must now pass it; states obtained from
`TreeController.getAnimationState` simply carry the new field.
- Added `avoidStickyHeaders` to `TreeController.animateScrollToKey`. When
true, the target lands just below the sticky band its own pinned ancestors
will form after the scroll instead of under it, and alignment works against
the viewport minus that band (bottom alignment is unchanged); the default,
false, keeps today's landings. `TreeController.stickyInsetOf` exposes the same
settled-extent inset for callers composing their own scroll math, and
`maxStickyDepthAcrossHosts` reports the largest `maxStickyDepth` among the
attached slivers.
- Changed: a pinned sticky header is no longer clipped to its own box when
the clip would cut nothing (the header is neither clamped by the paint region
nor mid-extent-animation). A header row whose child paints outside its box (a
shadow, an overflowing badge) now shows that overflow while pinned, matching
how the same row paints in flow; an app that relied on the pinned clip to
contain overflow should clip inside its own row widget.
- Fix: every reorderable row was wrapped in `Opacity(1.0)`, whose render
object is a compositing boundary at any alpha above zero, so each visible row
carried its own `OpacityLayer` on top of the package's `RepaintBoundary` and
`addRepaintBoundaries: false` could not remove it. The hide is now a
`Visibility` (size, state and animation maintained), which adds no layer and
also excludes focus while hidden: a focused field in the dragged row no
longer keeps primary focus while invisible.
- Changed: while the drag preview is shown (`showDragProxy: true`, the
default, or a `dragProxyBuilder`), the dragged subtree's in-place rows are
sized placeholders for the drag instead of hidden live copies, so row content
is inflated exactly once. Row `State` inside the dragged subtree is recreated
at lift and at drop unless the row content carries a `GlobalKey`, which now
migrates the element intact. A `GlobalKey` inside a row previously broke the
lift with a layout-phase assertion.
- Fix: a drag started on a sticky-pinned header resolved its drop target
against the content scrolled beneath the pinned strip. The drop probe now
consults the pinned band first, matching hit-testing, so the header itself is
the target while the pointer stays inside its band.
- Fix: standalone animations spawned by expand/collapse mutators (partial
reversals, nested-subtree exits, bulk continuations) ran on the `enterExit`
family's timing while the mutator's own kill switch read `expandCollapse`.
Each install site now declares its family and the standalone ticker resolves
the declared family through the live style, so restyling either family at
runtime retimes exactly its own in-flight states.
- Fix: measuring rows above the viewport shifted the content under the user by
the estimate-versus-measured residual, and `animateScrollToKey` landed off by
it. Layout now emits an anchor-preserving `scrollOffsetCorrection` for that
residual and `animateScrollToKey` snaps to the settled offset after the frame.
- Fix: a row taller than the cache extent left a viewport-sized hole below it,
because layout admission charged the leading row's out-of-window part against
the cache budget.
- Fix: `animateScrollToKey` issued right after a mutation (`insertRoot`,
`expand`) clamped to the pre-layout `maxScrollExtent` and rode its whole
duration to the wrong place. It now waits one frame for stale geometry and
follows in-flight tree animations to settled geometry.
- Fix: a superseded `animateScrollToKey` reported true while the position landed
elsewhere. Every scroll the controller starts is now single-flight in both
directions; a cancelled scroll resolves false.
- Fix: `expandAll(maxDepth:)` and `collapseAll(maxDepth:)` acted on group
direction instead of post-flip visibility, growing rows back under parents
that stayed collapsed or dragging still-visible rows to zero;
`collapseAll(maxDepth: 0, animate: false)` no longer empties the order.
- Fix: `expandAll` or `collapseAll` reversing an in-flight group re-targeted the
rows' animation envelopes without rebasing them, so the surviving rows popped
at the reversal. All four reversal sites now capture each row's painted extent
first.
- Fix: a row resized while a reversal was collapsing it (`collapse` during its
own `expand`, or `collapseAll`) jumped up to its new height mid-collapse; the
captured extent now stays the terminus.
- Fix: `expand` reversing an in-flight collapse left the animation caches stale
until the group completed, so the reversed rows were not treated as animating.
- Fix: an `expand` or `collapse` whose members were all pending deletion still
ran an empty animation group for a full duration (render cache off, one forced
layout per frame).
- Fix: `expand(animate: false)` during that subtree's collapse spliced the new
descendants as one block after the parent, misordering them against the
children still in the order.
- Fix: re-inserting a mid-exit node under a collapsed parent left a permanent
visible row.
- Fix: re-inserting an existing key under a comparator placed it one slot to the
right of its sorted position.
- Fix: a same-parent relocation notified only the moved key, so displaced
siblings kept stale positional inputs.
- Fix: `moveNode` to a different depth left rows collapsed earlier in the same
handler rendering at their pre-move depth.
- Fix: an inherited-widget read inside `nodeBuilder` (`Theme.of`) never
refreshed mounted rows when the inherited value changed.
- Fix: moving a `GlobalKey`-carrying widget out of a row dropped the row's
render box twice, once by the element and once by the framework.
- Fix: `syncRoots` computed root insert indices before its deferred removals, so
an exiting root was teleported to the bottom by the final reorder. Root
removals are now eager except for a root whose subtree holds a node moving
elsewhere.
- Fix: `syncRoots` purged a node moving out of a removed intermediate root
instead of deferring that removal until after the move.
- Fix: during bulk `expandAll`/`collapseAll` frames the sliver under-reported
its paint extent from stale per-row slots, rejecting taps below it and letting
a following sliver paint inside the tree.
- Fix: rows after the collapsing subtree were never admitted to layout during a
bulk `collapseAll`.
- Fix: the drop-target lookup over a slot the make-room preview had closed
resolved to the hidden dragged row instead of the row painted there.
- Fix: a settled exit ghost stayed painted and pinned for the whole of a drag
while a make-room preview was held.
- Fix: a settled edge ghost under a held make-room preview was painted by
neither paint pass, vanishing until the next layout.
- Fix: an exit-ghost anchor was painted twice per frame, the second paint
replacing the first's placement (no horizontal slide, wrong clip and z-order).
- Fix: a row sliding into a collapsed on-screen parent reported its stale
pre-move slot to `localToGlobal`, semantics and focus traversal for the
slide's duration.
- Perf: the bulk-only layout fast path fell off on every frame because its
per-row extent estimate never matched the measurement; the estimate is now the
measurement's own product form.
- Perf: K inserts under one parent inside `runBatch` built the sibling refresh
set K times (O(K * S)); it is built once per parent at batch exit.
- Perf: `syncChildren` no longer performs an O(N) list insert per inserted key.
- Changed: re-adding a mid-exit node with default flags restores the node, not
its in-flight subtree, matching `remove(animate: false)` followed by a fresh
add. Pass `preservePendingSubtreeState: true` to restore the subtree (the
declarative sync layers already do).
- Fix: a drag whose scrollable swapped its `ScrollPosition` mid-drag (the
`physics: isDragging ? const NeverScrollableScrollPhysics() : ...` pattern
does this on the first drag notification) stopped re-resolving the drop target
on external scrolls, because the session's listener stayed on the old
position. The subscription now follows the live position on every pointer
sample and autoscroll tick, and the new
`TreeReorderController.notifyScrollableChanged` (called by
`SliverReorderableTree` from the dragged row's `didChangeDependencies`)
re-binds it in the swap's own frame.
- Fix: under a `SliverPadding` (or any sliver that insets the tree in the cross
axis) the drag proxy spanned the whole viewport instead of the tree's band,
the x-aware drop resolution read the pointer offset by the inset, and the card
jumped by the inset at release. `ReorderRenderPort` gains
`crossAxisGlobalOrigin` and `crossAxisExtent`, which the proxy band and the
depth hint now use; `dragProxyBuilder`'s documented content width is
`sliverCrossAxisExtent - indent` (identical numbers for an unpadded tree).
- Fix: hot reload left mounted rows rendering the old `nodeBuilder` output
whenever an ancestor handed the same `SliverTree` instance down (the `child`
pass-through of `AnimatedBuilder`, `ValueListenableBuilder` and
`AnimatedTheme`), and when the ancestor built a fresh instance the reload
re-inflated every row, discarding row `State`. Rows now refresh in place on
every reload in both shapes and keep their `State`.

## 0.0.34

- **BREAKING** `SectionedListController.addItem` and `setItems` now throw
`ArgumentError` for an item key that belongs to another section, instead of
silently moving the item out of it. Use `moveItem` to move an item between
sections; re-adding an item to its own section is unchanged.
- **BREAKING** `SectionedListController.addSection` now throws `ArgumentError`
for a section key that already exists, and validates `items` before mutating,
so a rejected call no longer leaves an empty section behind. Re-adding a
section that is animating out still cancels its removal.
- Fix: a downward drag onto a collapsed or leaf row committed the node as that
row's sibling instead of into it. The probe was landing in the gap the
make-room preview had just opened and re-resolving against the row below it.
- Fix: starting or moving a drag between a structural mutation and the next
frame could throw a `RangeError` or report another row's geometry, because the
row lookup read layout caches the mutation had invalidated.
- Fix: `animateScrollToKey` with `AncestorExpansionMode.animated` kept driving
a disposed `ScrollPosition` when the scrollable was rebuilt mid-scroll, which
asserted in debug and silently abandoned the scroll in release.
- Fix: three defects in `TreeSyncController`'s expansion memory let a sync
override the user's expand or collapse across a remove and re-add: a
descendant hidden under a collapsed ancestor lost its entry, a root re-added
without children was never restored once they arrived, and a second removal
while childless overwrote the remembered state.
- Fix: `SectionedSliverList` ignored `preserveExpansion`, because every sync
re-applied the initial-expansion policy to re-added sections. Sections now
come back as the user left them, matching `SyncedSliverTree`; pass
`preserveExpansion: false` for the old behavior.
- Fix: `TreeSyncController.syncMultipleChildren` destroyed a moved node's own
children when `animate` was false and the node's old parent was removed in the
same call.
- Fix: `SectionedListController.moveItem` brought back an item that was
animating out when given a `toSection`; the in-section form already refused.
- Fix: `SectionedListController.moveItem(toSection:)` with no `index` did
nothing when the item was already in that section, instead of appending it as
documented.
- Fix: disposing a `TreeReorderController` mid-drag and rebuilding with a new
one left the dragged row invisible and its drag proxy stuck in the overlay.
- Fix: the dragged row's hidden copy was still hit-testable, so a second finger
landing on it could cancel the drag or fire that row's tap handlers. Every
other row stays interactive.
- Fix: dragging a subtree taller than the scrollable's cache extent left blank
space where the make-room preview had shifted rows into view. Re-targeting the
gap now costs one layout, independent of frame rate.
- Perf: a batch of K animated mutations took K full visible-order snapshots to
stage one slide baseline. Measured on 4000 rows with 400 batched moves, 465ms
to 176ms.
- Perf: a drag suspended stale-row eviction for its whole duration, so every
row an autoscroll drag passed stayed mounted until the drop. Measured on 2000
rows over 200 frames, 143 mounted rows to 25 against a steady state of 18.
- Perf: scrolling inside a subtree whose sticky header is pinned rebuilt a
prefix sum over every visible row on each frame, because the header's own row
is mounted from outside the cache region.
- Added `SectionedListController.rememberedSectionKeys()`, the section keys
whose expansion state is held for a re-add. It replaces the undocumented
`debugSnapshotRememberedSectionKeys()`.

## 0.0.33

- Fix: removing a visible row that had never been laid out collapsed its
extent in one frame instead of animating out. The exit now starts from the
same estimate fallback the collapse path uses.
- Fix: a sticky header pinned while ENTERING snapped to full height instead of
growing in. The band takes the animated extent while entering; exiting stays
on the settled extent so the header retires by push-up.
- Fix: an entering root that took the sticky band over at a scrolled offset
popped in flush at the band top instead of sliding down into it.
- Fix: the pinned header vanished or mispositioned for the whole duration of
an `expandAll` / `collapseAll` that moved the offsets of a pinned section
whose header row sits outside the cache region.
- Fix: the sticky band went blank for the whole duration of a diff that added
or removed a depth-0 root. Animation membership no longer affects candidate
eligibility, and the 1-in-3 recompute throttle and the paint-time skip for
exiting headers are gone with it.
- Fix: a row that was both sticky and an exit-ghost anchor was painted by
neither pass while exiting; the sticky pass now paints exiting headers.
- Perf: sticky headers take one candidate walk per layout instead of two
(`identifyPotentialStickyNodes` and `computeStickyHeaders` are merged).
- Added `RenderSliverTree.debugLastPaintedStickyKeys`, the keys the sticky
paint pass actually painted this frame; assert-guarded.
- Fix: `TreeController.remove` did not flush a deferred visible-order rebuild
before reading the order, so inside `runBatch` its animated-versus-immediate
path gate read stale state. Only batched sequences were affected.
- Perf: the floating drag proxy is built once per drag session and
repositioned as a retained subtree instead of rebuilding on every pointer
move. Proxy content that self-drives motion or drag-state reactivity still
works, since the subtree stays mounted for the whole session.
- Fix: rebuilding `SliverReorderableTree` with a different
`TreeReorderController` mid-drag stranded the session, leaving rows shifted
and leaking its eviction pin, scroll listener and autoscroll ticker.
- Fix: a `TreeSyncController.syncRoots(childrenOf:)` that throws during
desired-tree validation left the internal desired-descendants set populated,
silently skipping removals in every later `syncChildren`.
- **BREAKING** `SyncedSliverTree.flat` now throws `ArgumentError` when
`parentOf` returns a key absent from `items`, listing every offending
(child, parent) pair; such items used to be silently treated as roots.
Returning null from `parentOf` is the explicit way to make an item a root.
- **BREAKING** `preserveExpansion` and `maxExpansionMemorySize` merge into one
`expansionMemory` parameter on `TreeSyncController` and all three
`SyncedSliverTree` constructors: the maximum number of removed nodes whose
expansion state is remembered for restore on re-add, 0 disabling the memory
entirely (default `TreeSyncController.defaultExpansionMemory`, 1024).

  Migration: `preserveExpansion: false` becomes `expansionMemory: 0`,
  `maxExpansionMemorySize: N` becomes `expansionMemory: N`, and both set
  becomes `expansionMemory: preserveExpansion ? N : 0`.
  `SectionedSliverList.preserveExpansion` and
  `SectionedListController.preserveExpansion` are unchanged.
- Added `TreeReorderConfig.enabled` (default true), the tree-wide runtime
reorder toggle: it disarms every handle, withdraws the reorder semantics
actions, refuses programmatic `TreeReorderController.moveTo`, and ends a drag
already in flight, with no change to any row's widget shape. It dominates
`canReorder`, which stays the per-row policy.
- **BREAKING** `SliverReorderableTree.indentPerDepth` and
`TreeReorderConfig.indentPerDepth` are renamed `indentWidth`, matching the
`TreeController` / `SyncedSliverTree` name for the same constant;
`SliverReorderableTree.indentWidth` is now `double?` defaulting to null, which
resolves to `TreeController.indentWidth` at drag start instead of a hardcoded
24.0. Behavior note: a tree rendering with the controller's default
`indentWidth: 0` no longer gets a phantom 24 px hint column, so pass
`indentWidth: 24.0` to keep the old mapping.
- Fix: the drag tunings (`autoExpandDelay`, `autoScrollEdgeZone`,
`autoScrollMaxVelocity`) on `TreeReorderConfig` / `SectionedReorderConfig` are
now live on rebuild instead of read once at construction. Each value is
captured per drag session, so a change applies from the next drag.
- Fix: dragging an EXPANDED parent now carries its whole visible subtree: the
in-place rows all hide, the proxy stacks a clone per visible descendant
(frozen at lift, drawing capped at one viewport), and all three settle glide
paths carry every subtree row. A custom `dragProxyBuilder` still styles only
the dragged row's portion.
- Fix: cross-depth drags are now seamless horizontally as well as vertically:
the proxy carries an animated left padding toward the drop target's column,
and every settle glide starts at the proxy's instantaneous visual cross offset
instead of a structural x. Internal:
`ReorderRenderPort.beginSlideBaseline` takes `baselineOverrides`, and
`startDrag` gained an optional `proxyCrossOffset` closure.
- **BREAKING** removed the `SyncedSliverTree.nodes` and `.snapshot`
constructors and `TreeSnapshot`; the three remaining input modes cover the
same ground. `withMove` callers apply the move to their own model: remove the
key from its old parent first, then insert at the reported index, which names
a FINAL-list position.
- Fix: `SectionedListController.moveItem(index:)` dropped `animate` on the
in-section path, so `animate: false` slid anyway. `reorderItems` and
`ItemView.moveTo` gained matching `animate` parameters.
- The declarative `SectionedSliverList` now skips the diff when `sections` is
the `identical` instance from the previous build; `itemsOf` is excluded from
the check and must be pure.
- Perf: `childrenOf` is consulted exactly once per node per sync, and is now
documented as required to be a pure function of its argument.
- Added `TreeSyncController.snapshotChildPresence()`: every live key mapped to
whether it has live children, with no per-node child-list copies.
- **BREAKING** drag handles are now placed by the CALLER: removed
`TreeRowDragMode` (with `TreeRowLongPressDrag` / `TreeRowHandleDrag` /
`TreeRowManualDrag`), `TreeDragHandleBuilder`, the `rowDragMode` /
`itemDragMode` / `sectionDragMode` config fields, `ReorderableNodeWrapper`,
the `wrap` parameter of `SliverReorderableTree.nodeBuilder`, and the
`draggable` members of `TreeItemView` / `SectionView` / `ItemView`, replaced
by `TreeDragHandle` and `TreeDelayedDragHandle` plus `TreeRowDragScope`.
`nodeBuilder` reverts to `(context, key, depth)` and every row is wrapped
unconditionally, so a row with no handle cannot be lifted but is still a drop
target with its reorder semantics actions.

  Migration:
  `nodeBuilder: (c, k, d, wrap) => wrap(longPressToDrag: true, child: row)`
  becomes `nodeBuilder: (c, k, d) => TreeDelayedDragHandle(child: row)`.
- **BREAKING** `TreeReorderConfig.rowDragMode` is replaced by
`buildDefaultDragHandles` (default TRUE, matching `ReorderableListView`), and
`SectionedReorderConfig` gets the per-kind pair `buildDefaultItemDragHandles`
/ `buildDefaultSectionDragHandles`; callers who never typed a drag mode need
no migration, while `.handle` / `.manual` callers set the flag false and place
a handle in their builder. Behavior notes: a `canReorder`-refused grip now
renders visibly (disarmed) instead of hidden with reserved width, and a handle
drag accepts on distance in ANY direction.
- Fix: grab geometry when a drag starts on a PINNED sticky header (the card
jumped on pickup and the proxy rendered at the wrong height).
`ReorderRenderPort` gained `paintedRowBounds(key)`.
- Fix: `.hierarchy` input reversed the ROOT order for multi-root input
(`[a, b, c]` came out `[c, b, a]`); child order was unaffected.
- `TreeItemView` gained `indexInParent`, `siblingCount`, `isFirst` and
`isLast`, all live-space (siblings animating out are excluded).
- Fix: rows now rebuild when a sibling insert, removal, reorder or move shifts
their position; sibling mutations declare the whole sibling list as affected.
- **BREAKING** removed `TreeItemView.watch`, `SectionView.watch` and
`ItemView.watch`: rows already rebuild when their own rendered inputs change,
so read the properties inline. The controller payload listeners and
`TreeNodeBuilder` are unaffected.
- `TreeController` gained an expansion-listener channel:
`addExpansionListener` / `removeExpansionListener` report `(key, isExpanded)`
for every state flip, `expandAll` / `collapseAll` included. Node lifecycle
resets are silent, and `runBatch` coalesces per key.
- `SyncedSliverTree` gained `onExpansionChanged` (its own initial expansion
pass is silent), `initialNodeExpansion` (per-node initial policy
`(key, item) -> bool?`, null defers to `initiallyExpanded`), and
`onControllerCreated` (one-shot handover of the internal `TreeController`
after the first sync; do not dispose it).
- **BREAKING (behavior)** the no-op rebuild fast path compares only the mode's
collection instance, not the extractor callbacks (`keyOf`, `childrenOf`,
`parentOf`), which must now be pure functions of their input. Pass a new
collection instance to signal change, the `ListView.children` convention.
- Fix: starting a drag while a previous drop's slides were still running left
drop-target resolution on an O(rows) scan per pointer event for the whole
drag. Edge ghosts now retire on FLIP-slide state via the new
`TreeController.hasActiveFlipSlides` / `getFlipSlideDeltaNid`; painted
positions, hit-testing, retention and overreach still read the composed
`hasActiveSlides` / `getSlideDeltaNid`.
- Fix: a row sliding IN from off-screen during a drag popped in at the
viewport boundary instead of gliding in from beyond the edge, because the
slide-install path mistook a held make-room offset for an in-flight slide.
The same misread also installed pointless slides for rows off-screen on both
sides of such a mutation.
- Perf: `expand()` and `collapse()` on an idle tree no longer pay an
O(subtree) slide-baseline staging cost per call, and `collapse()` walks its
visible descendants once instead of twice. Behavior is unchanged whenever
slides are active.
- Perf: `getIndexInParent` is now O(1) amortized instead of an O(siblings)
scan per call, so drop-target resolution during a drag and the per-row
semantics-action builders no longer rescan wide sibling lists. The live-space
contract and return values are unchanged.

## 0.0.32

- Fix: parent rows that render their child count now refresh whenever the count
changes, not only when `hasChildren` flips. Previously a parent kept its
pre-removal count after an animated child removal, most visibly as stale
`SectionedSliverList` header item counts.
- `TreeItemView` gained `liveChildCount` / `hasLiveChildren`, counts that
exclude children animating out for builders that want the settled state rather
than the painted state (`childCount` keeps matching the rows still on screen).
- **BREAKING** one `TreeAnimationStyle` now configures every animation family:
`expandCollapse`, `enterExit` (falls back to `expandCollapse`), `reorderSlide`,
`makeRoom` and `dropSettle` (fall back to `reorderSlide`). Removed in favor of
`animationStyle`: `TreeController.animationDuration` / `animationCurve`,
`TreeReorderController.slideDuration` / `slideCurve`, and the
`animationDuration` / `animationCurve` params on all `SyncedSliverTree`
constructors, `SectionedSliverList` and `SectionedListController`.

  Migration: replace `animationDuration: D, animationCurve: C` with
  `animationStyle: TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: D, curve: C))`,
  and `animationDuration: Duration.zero` with
  `animationStyle: TreeAnimationStyle.disabled`. Use
  `TreeAnimationStyle.uniform(duration:, curve:)` for one spec everywhere.
- **BREAKING (behavior)** the zero-duration kill switch is per-family: a family
resolving to `Duration.zero` snaps and dominates explicit per-call durations,
and each drag family gates on its own spec (so `dropSettle` glides still run
when `reorderSlide` is zeroed). A zero family creates no motion but no longer
drops other families' in-flight slides; restyling `reorderSlide` to zero at
runtime still stops in-flight slides.
- **BREAKING (behavior)** uniform defaults: all five families now default to
300ms / `Curves.linear`, from one shared `TreeAnimationStyle.defaultSpec`. The
old per-family defaults, now gone, were 300ms / `Curves.easeInOut` for
expand/collapse and 220ms / `Curves.easeOutCubic` for slide and preview; pass an
explicit spec to restore either.
- `reorderRoots` / `reorderChildren` gained per-call `slideDuration` /
`slideCurve` overrides and now read the `reorderSlide` family, so keyboard
reorder semantics actions animate consistently with `moveNode`. Sync-driven
moves and reorders keep riding `expandCollapse` to stay in lockstep with
same-batch extent animations.
- `moveNode` / `animateSlideFromOffsets` / `setReorderPreview` /
`clearReorderPreview` timing params are now optional, defaulting to the style's
family specs.
- Fix: `expandAll` / `collapseAll` completion no longer reports the finished
bulk group's members as still animating.
- Perf: `setReorderPreview` scans only the visible order and memoizes unchanged
drop slots, so pointer-dwell re-sends skip the target recomputation entirely.
- Perf: `findRowAtPaintedY` uses an O(window) bounded scan during drags instead
of an O(visible) scan per pointer event. `maxActiveSlideAbsDelta` is now
test-only; production reads the new `composedSlideAbsDeltaBound`.
- Drag-and-drop example: the duration slider restyles live.

## 0.0.31

- **BREAKING** the drop-indicator line is gone; the make-room preview is now
the only drop-feedback paradigm. Removed `SliverReorderableTree`'s
`showDropIndicator`, `dropIndicatorColor`, `dropIndicatorThickness`,
`makeRoomOnDrag` (always on), and `draggedOpacity` (the dragged row's
in-place copy is always hidden so its slot can close).
- **BREAKING** `SliverReorderableTree.showDragProxy` now defaults to `true`,
because make-room hides the dragged row and without a proxy nothing follows the
pointer. The proxy renders in the root `Overlay` outside the row's ancestry,
so Material rows need a `dragProxyBuilder` re-providing a `Material`
ancestor.
- Consequence of the two above: drags are now CARD-ANCHORED by default, so slot
selection probes at the floating proxy's midpoint rather than the raw
pointer. Pass `showDragProxy: false` for the raw-pointer probe.
- `indentPerDepth` is retained, but now serves only the pointer-x to drop-depth
mapping at subtree boundaries.

## 0.0.30

- Internal refactor of the drag-and-drop reorder stack into per-session
collaborators; no public API changes.
- Perf: fewer render-tree lookups per pointer move during drags.
- `startDrag` against an already-unmounted scrollable now returns `false`
instead of asserting.

## 0.0.29

- Touch-first drag anchoring: slot selection follows the floating card's
midpoint in make-room + proxy sessions (the finger hides under the card).
- Fix: handle-drag grab geometry skew caused by touch-slop acceptance.
- Mid-drag gesture-mode swaps now cancel the session cleanly.
- Fix: throw when a drag ends after the scrollable was unmounted.
- Added opt-in `SliverReorderableTree.hapticsOnDrag`.
- Workspaces example: handle-mode / touch-mode toggle.

## 0.0.28

- Re-resolve the drop target on any scroll (wheel / trackpad / autoscroll),
not just pointer moves.
- X-aware drop depth at subtree boundaries (pick nesting level from the
pointer's horizontal position).
- Hover-dwell auto-expand of collapsed drop targets (`autoExpandDelay`).
- Reorder semantics (accessibility) actions on wrapped rows.
- Floating drag proxy (`showDragProxy` / `dragProxyBuilder`); drops settle
from the release position instead of replaying the old-slot slide.
- Make-room preview (`makeRoomOnDrag`): rows part to open a paint-only gap
at the prospective slot; the drop lands with zero jump.
- Eliminate drop-zone dead zones ("returns here" targets, two-zone split
under `into` vetoes) and section-boundary gap oscillation.
- Discard FLIP baselines staged without a following mutation.
- Added `TreeController.liveChildCount` / `liveRootCount`.

## 0.0.27

- **BREAKING** drag-and-drop reorder API refactor: `TreeReorderController`
is key-only (`<TKey>`), `startDrag` takes a `ReorderRenderPort` and
returns `bool` for policy refusals, and `TreeDropTarget` is purely
semantic (indicator geometry derived by the widget layer).
- Added `SliverReorderableTree.showDropIndicator` to disable the built-in
indicator line.
- Added `TreeController.hasLiveChildren` / `hasComparator`.
- Fix: double-invoked drag-UI teardown in `SliverReorderableTree`.

## 0.0.26

- `TreeSyncController` / `SectionedListController`: syncs now diff against
controller truth; a desired list that still contains a removed (mid-exit) key
resurrects it. Derive mirrored state from live reads (`getLiveChildren` /
`liveItemsOf`) to preserve imperative removals.
- `TreeController.animateScrollToKey`: animated-mode scrolls are now
single-flight: starting a new scroll cancels the one in flight (its future
resolves false).

## 0.0.25

- Animate same-parent reorders in `SyncedSliverTree`.

## 0.0.24

- Fix: reparenting between a non-collapsed and a collapsed node.

## 0.0.23

- Fix: occlusion / z-order of a tall card reparented into a collapsed section.

## 0.0.22

- Fix: reparenting into collapsed section.

## 0.0.21

- Minor bug fixes.

## 0.0.20

- Minor clean-ups.
- Minor bug fixes.

## 0.0.19

- Fix: orphaned animation entry staying during quick filtering.
- Perf: minor optimizations.

## 0.0.18

- Fix: `SyncedSliverTree` / `TreeSyncController` reparent animation skip when
parent is deleted.

## 0.0.17

- Use animated `moveTo` in `SyncedSliverTree`.

## 0.0.16

- `SectionedSliverList` public surface trimmed and restructured. Same underlying
engine; new ergonomics.
- Added animations to `moveTo`.

## 0.0.15

- Fix: root node ordering regression caused by switching from recursive to
iterative. Root nodes were being reversed.

## 0.0.14

- Fix: animation of nested collapsing/expanding nodes when parent collapse or
expand state is toggled mid-animation.
- Fix: animation collapse-expand-collapse behavior.

## 0.0.13

- Added `SectionedSliverList`: a header + items convenience sliver built
on top of `SliverTree`.
- Fix: animation issue when adding/removing many times quickly.
- Fix: visible-subtree-size cache desync across all node-purge paths.
- Fix: node removal desync.
- Replace recursive code with iterative.
- Added various tests.

## 0.0.12

- Fix: missing case to clip content above viewport when at max extent.
- Fix: animation skip when drag and dropping a collapsing node.
- Perf: optimized collapsing of nodes with many children.
- Fix: visual flicker when collapsing a node with many children.

## 0.0.11

- Stale node eviction.
- Fix: scroll-to-node jump.

## 0.0.10

- Perf: optimized expansion of nodes with many children.

## 0.0.9

- Fix: re-insert animation regression.
- Fix: expansion persistence regression.

## 0.0.8

- Added `animateScrollToKey`: scroll to node by key.
- Various fixes and optimizations.

## 0.0.7

- Added `SyncedTreeNode` and new constructors.

## 0.0.6

- Refactor `TreeMapView` into `SyncedSliverTree`.

## 0.0.5

- Added test for expansion memory during animated removal and re-addition.

## 0.0.4

- Fix: expansion state for multi-sync.

## 0.0.3

- Fix: expansion state history.

## 0.0.2

- Fix: expanding a child node that has a collapsed parent (previously ignored
expansion).
- Made child sync recursive for `SyncedSliverTree` and `TreeSyncController`.

## 0.0.1

- Added `sliver_tree`: a node based sliver that supports tree-like nesting for
data.
