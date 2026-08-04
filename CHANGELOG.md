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
