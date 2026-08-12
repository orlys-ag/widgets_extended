## Unreleased

- **BREAKING** `SliverReorderableTree.indentPerDepth` and
`TreeReorderConfig.indentPerDepth` are renamed `indentWidth`, matching the
`TreeController` / `SyncedSliverTree` name for the same pixels-per-depth
constant. `SliverReorderableTree.indentWidth` is now `double?` defaulting to
null, which resolves to `TreeController.indentWidth` at drag start instead of
a hardcoded `24.0`; set it explicitly only when rows bake their own indent.
Behavior note: a tree rendering with the controller's default `indentWidth: 0`
no longer gets a phantom 24 px hint column; x-aware depth selection is
disabled and below-boundary drops resolve at the deepest legal level. Pass
`indentWidth: 24.0` to keep the old mapping.
- Fix: the drag tunings (`autoExpandDelay`, `autoScrollEdgeZone`,
`autoScrollMaxVelocity`) on `TreeReorderConfig` / `SectionedReorderConfig` are
now live on rebuild instead of silently read once at construction. The
backing `TreeReorderController` fields are mutable; each value is captured
per drag session at `startDrag`, so a change applies from the next drag.
- `TreeSyncController`'s expansion-memory gating is unified internally, and
`maxExpansionMemorySize: 0` is documented as equivalent to
`preserveExpansion: false`. No behavior change.
- Fix: dragging an EXPANDED parent now carries its whole visible subtree: the
in-place rows all hide, the floating proxy stacks a clone per visible
descendant (captured frozen at lift; drawing capped at one viewport), and all
three settle glide paths (commit, cancel, dead-commit) carry every subtree
row. A custom `dragProxyBuilder` still receives and styles only the dragged
row's portion; leaf and collapsed-parent drags are unchanged.
- Fix: cross-depth drags are now seamless horizontally as well as vertically:
the proxy carries an animated left padding from the source row's indent
toward the drop target's column (riding the `makeRoom` family), and every
proxy-to-row settle glide starts at the proxy's instantaneous visual cross
offset instead of a structural x. Internal:
`ReorderRenderPort.beginSlideBaseline` now takes
`baselineOverrides: Map<TKey, ({double y, double? x})>?` (null x keeps the
captured cross offset), and `startDrag` gained an optional
`proxyCrossOffset` closure.
- **BREAKING** removed the `SyncedSliverTree.nodes` and `.snapshot`
constructors and `TreeSnapshot`. The three remaining input modes cover the
same ground: keep structure in nested `SyncedTreeNode`s (the default
constructor), or project domain objects through `.hierarchy` / `.flat` (same
validation, now run directly at sync time). `withMove` callers apply the move
to their own model: remove the key from its old parent first, then insert at
the reported index, which names a FINAL-list position (see the tutorial's
section 9 for a worked implementation).
- Fix: `SectionedListController.moveItem(index:)` dropped `animate` on the
in-section path, so `animate: false` slid anyway. It forwards now;
`reorderItems` and `ItemView.moveTo` gained matching `animate` parameters,
and the docs no longer claim in-section reorders never animate.
- The declarative `SectionedSliverList` now skips the diff when `sections` is
the `identical` instance from the previous build (the `SyncedSliverTree` /
`ListView.children` convention); `itemsOf` is excluded from the check and
must be pure. `hideEmptySections` no longer evaluates `itemsOf` an extra time
per section.
- Perf: `childrenOf` is consulted exactly once per node per sync (both sync
walks used to call it independently), and is now documented as required to be
a pure function of its argument.
- Added `TreeSyncController.snapshotChildPresence()`: every live key mapped
to whether it has live children, with no per-node child-list copies.
`SyncedSliverTree`'s expansion passes use it, and are skipped entirely when
neither can do anything.
- **BREAKING** drag handles are now placed by the CALLER. Removed
`TreeRowDragMode` (with `TreeRowLongPressDrag` / `TreeRowHandleDrag` /
`TreeRowManualDrag`), `TreeDragHandleBuilder`, the `rowDragMode` /
`itemDragMode` / `sectionDragMode` config fields, `ReorderableNodeWrapper`,
the `wrap` parameter of `SliverReorderableTree.nodeBuilder`, and the
`draggable` members of `TreeItemView` / `SectionView` / `ItemView`. New:
`TreeDragHandle` and `TreeDelayedDragHandle` (draw nothing, only arm their
child; any placement, size or count) plus `TreeRowDragScope`. `nodeBuilder`
reverts to the plain `(context, key, depth)` signature and every row is
wrapped unconditionally; a row with no handle cannot be lifted by a pointer
but is still a drop target and keeps its reorder semantics actions.
Migration: `nodeBuilder: (c, k, d, wrap) => wrap(longPressToDrag: true,
child: row)` becomes `nodeBuilder: (c, k, d) =>
TreeDelayedDragHandle(child: row)`.
- **BREAKING** `TreeReorderConfig.rowDragMode` is replaced by
`buildDefaultDragHandles` (default TRUE, matching `ReorderableListView`);
`SectionedReorderConfig` gets the per-kind pair
`buildDefaultItemDragHandles` / `buildDefaultSectionDragHandles`. Callers who
never typed a drag mode need no migration; `.handle` / `.manual` callers set
the flag false and place a `TreeDragHandle` / `TreeDelayedDragHandle` in
their builder. Behavior notes: a `canReorder`-refused grip now renders
visibly (disarmed) instead of hidden with reserved width; reproduce the old
look with `TreeRowDragScope.maybeOf(context)?.canDrag` plus
`Visibility(maintainSize: true)`. A handle drag accepts on distance in ANY
direction, and an armed handle is hit-opaque while a disarmed one is not.
- Fix: grab geometry when a drag starts on a PINNED sticky header (the card
jumped on pickup and the proxy rendered at the wrong height).
`ReorderRenderPort` gained `paintedRowBounds(key)`, and the grab path asks
where its own row is painted instead of what sits at the pointer's y.
- Fix: `.hierarchy` input reversed the ROOT order for multi-root input
(`[a, b, c]` came out `[c, b, a]`); child order was unaffected.
- `TreeItemView` gained `indexInParent`, `siblingCount`, `isFirst` and
`isLast`, all live-space (siblings animating out are excluded).
- Fix: rows now rebuild when a sibling insert, removal, reorder or move
shifts their position; sibling mutations declare the whole sibling list as
affected (previously only the parent, or nothing for pure reorders).
- **BREAKING** removed `TreeItemView.watch`, `SectionView.watch` and
`ItemView.watch`: rows already rebuild when their own rendered inputs change,
so read the properties inline. The controller payload listeners and
`TreeNodeBuilder` (observation from outside the rows) are unaffected.
- `TreeController` gained an expansion-listener channel:
`addExpansionListener` / `removeExpansionListener` report `(key, isExpanded)`
for every state flip, `expandAll` / `collapseAll` included. Node lifecycle
resets are silent, and `runBatch` coalesces per key.
- `SyncedSliverTree` gained `onExpansionChanged` (its own initial expansion
pass is deliberately silent), `initialNodeExpansion` (per-node initial
policy `(key, item) -> bool?`, null defers to `initiallyExpanded`; never
overrides a user toggle or remembered state), `onControllerCreated` (one-shot
handover of the internal `TreeController` after the first sync; do not
dispose it), and `maxExpansionMemorySize` (default 1024; 0 disables expansion
memory).
- **BREAKING (behavior)** the no-op rebuild fast path compares only the
mode's collection instance, not the extractor callbacks (`keyOf`,
`childrenOf`, `parentOf`), which must now be pure functions of their input.
Pass a new collection instance to signal change, the `ListView.children`
convention.
- Fix: starting a drag while a previous drop's slide animations were still
running left the drag resolving drop targets with an O(rows) scan per pointer
event, for the whole drag. Edge ghosts (rows whose slide destination is
off-screen) are retired on FLIP-slide state instead of the composed
slide-plus-preview state: because a make-room preview offset is HELD for the
duration of a drag, the composed reads never reported the slide as finished,
so the cleanup pass was never scheduled and the stale ghosts kept failing the
fast path's precondition. Most visible on wide lists, where the scan is
longest. `TreeController` gains `hasActiveFlipSlides` and
`getFlipSlideDeltaNid` for this; painted positions, hit-testing, retention
and overreach continue to read the composed `hasActiveSlides` /
`getSlideDeltaNid` and are unchanged.
- Fix: a row sliding IN from off-screen during a drag (a mutation lands
while the make-room preview is holding rows shifted, e.g. a dwell-expand or
an app-driven update mid-drag) popped in at the viewport boundary instead of
gliding in from beyond the edge. The slide-install path mistook the held
preview offset for an in-flight slide and took the composition clamp (just
inside the edge) instead of the initial-install clamp (edge plus overhang).
The same misread also installed pointless slides for rows off-screen on both
sides of such a mutation, which prolonged the FLIP-active window and with it
the edge-ghost cleanup the previous fix keyed to it.
- Perf: `expand()` and `collapse()` on an idle tree no longer pay an
O(subtree) slide-baseline staging cost per call. Staging is now gated by the
O(1) `hasActiveSlides` check before any per-row work, so the descendant
materialization and the per-row slide probes run only while a slide or a
held drag preview is actually active. `collapse()` also walks its visible
descendants once instead of twice. Behavior is unchanged whenever slides
are active.
- Perf: `getIndexInParent` is now O(1) amortized instead of an O(siblings)
scan per call. Drop-target resolution during a drag (several lookups per
pointer move and per autoscroll tick) and the per-row semantics-action
builders no longer rescan wide sibling lists: the first lookup after any
mutation refreshes the touched list once, and every following lookup is a
constant-time cache read until the next mutation. Most visible dragging
over wide flat sections. The live-space contract and return values are
unchanged, including for keys read by a user `comparator` mid-mutation.

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
- Fewer render-tree lookups per pointer move during drags.
- `startDrag` against an already-unmounted scrollable now returns `false`
instead of asserting.

## 0.0.29

- Touch-first drag anchoring: slot selection follows the floating card's
midpoint in make-room + proxy sessions (the finger hides under the card).
- Fix handle-drag grab geometry skew caused by touch-slop acceptance.
- Mid-drag gesture-mode swaps now cancel the session cleanly.
- Fix throws when a drag ends after the scrollable was unmounted.
- New opt-in `SliverReorderableTree.hapticsOnDrag`.
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
- New `TreeController.liveChildCount` / `liveRootCount`.

## 0.0.27

- **BREAKING** drag-and-drop reorder API refactor: `TreeReorderController`
is key-only (`<TKey>`), `startDrag` takes a `ReorderRenderPort` and
returns `bool` for policy refusals, and `TreeDropTarget` is purely
semantic (indicator geometry derived by the widget layer).
- New `SliverReorderableTree.showDropIndicator` to disable the built-in
indicator line.
- New `TreeController.hasLiveChildren` / `hasComparator`.
- Fix double-invoked drag-UI teardown in `SliverReorderableTree`.

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

- Fix reparenting between a non-collapsed and a collapsed node.

## 0.0.23

- Fix occlusion / z-order of a tall card reparented into a collapsed section.

## 0.0.22

- Fix reparenting into collapsed section.

## 0.0.21

- Minor bug fixes.

## 0.0.20

- Minor clean-ups.
- Minor bug fixes.

## 0.0.19

- Fix orphaned animation entry staying during quick filtering.
- Minor optimizations.

## 0.0.18

- `SyncedSliverTree` / `TreeSyncController`: fix reparent animation skip when
parent is deleted.

## 0.0.17

- Use animated `moveTo` in `SyncedSliverTree`.

## 0.0.16

- `SectionedSliverList` public surface trimmed and restructured. Same underlying
engine; new ergonomics.
- Added animations to `moveTo`.

## 0.0.15

- Fix root node ordering regression caused by switching from recursive to
iterative. Root nodes were being reversed.

## 0.0.14

- Fix animation of nested collapsing/expanding nodes when parent collapse or
expand state is toggled mid-animation.
- Fix animation collapse-expand-collapse behavior.

## 0.0.13

- Add `SectionedSliverList`: a header + items convenience sliver built
on top of `SliverTree`.
- Fix animation issue when adding/removing many times quickly.
- Fix visible-subtree-size cache desync across all node-purge paths.
- Fix node removal desync.
- Replace recursive code with iterative.
- Add various tests.

## 0.0.12

- Fix missing case to clip content above viewport when at max extent.
- Fix animation skip when drag and dropping a collapsing node.
- Optimize collapsing of nodes with many children.
- Fix visual flicker when collapsing a node with many children.

## 0.0.11

- Stale node eviction.
- Scroll to node jump fix.

## 0.0.10

- Optimized expansion of nodes with many children.

## 0.0.9

- Fix re-insert animation regression.
- Fix expansion persistence regression.

## 0.0.8

- Added `animateScrollToKey`: scroll to node by key.
- Various fixes and optimizations.

## 0.0.7

- Add `SyncedTreeNode` and new constructors.

## 0.0.6

- Refactor `TreeMapView` into `SyncedSliverTree`.

## 0.0.5

- Add test for expansion memory during animated removal and re-addition.

## 0.0.4

- Fix expansion state for multi-sync.

## 0.0.3

- Fix expansion state history.

## 0.0.2

- Fix expanding a child node that has a collapsed parent (previously ignored
expansion).
- Made child sync recursive for `SyncedSliverTree` and `TreeSyncController`.

## 0.0.1

- Adds `sliver_tree`: a node based sliver that supports tree-like nesting for
data.
