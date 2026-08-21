## Unreleased

- Fix: `SectionedSliverList`'s `preserveExpansion` had no effect. Every
sync re-applied the initial-expansion policy to any section that was not
live before it, which is every re-added section, overwriting the state
the memory had just restored. A section the user collapsed now comes
back collapsed, and one they expanded comes back expanded, matching
`SyncedSliverTree`. Callers who relied on the old behavior can set
`preserveExpansion: false`.
- **BREAKING** `SectionedListController.addItem` and `setItems` now throw
`ArgumentError` for an item key that belongs to another section, instead
of silently moving the item out of it. Use `moveItem` to move an item
between sections. Re-adding an item to its own section is unchanged
(an upsert, or a cancel of a pending removal).
- **BREAKING** `SectionedListController.addSection` now throws
`ArgumentError` for a section key that already exists, and validates its
`items` before mutating, so a rejected call no longer leaves an empty
section behind. Re-adding a section that is animating out still cancels
its removal.
- Fix: `SectionedListController.moveItem` resurrected an item that was
animating out when it was given a `toSection`; the in-section form
already refused. Both forms now refuse.
- Fix: `SectionedListController.moveItem(toSection:)` with no `index` is
documented to append, but was a no-op when the item was already in that
section.
- Fix: the dragged row's hidden in-place copy was still hit-testable, so
a second finger landing on it could kill the drag (a touch on one of the
row's own handles ran the re-entry guard) or fire that row's tap
handlers. The hidden copy now ignores pointers; every other row stays
interactive.
- Fix: a make-room drag suspended stale-row eviction for its whole
duration, so every row an autoscroll drag passed stayed mounted until
the drop (2000 rows over 200 frames: 18 mounted rows became 143).
Eviction and retention now read the FLIP-slide state, which goes idle,
rather than the composed state, which a held preview never lets go idle.
- Fix: dragging a subtree taller than the scrollable's cache extent left
blank space where the make-room preview had shifted rows into the
viewport. Preview offsets are paint-only, so nothing widened the layout
admission window until autoscroll or the drop forced a layout. The
window now widens once per re-target.
- Added `SectionedListController.rememberedSectionKeys()`, the section
keys whose expansion state is held for a re-add. It replaces the
undocumented `debugSnapshotRememberedSectionKeys()`.

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
