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
single-flight — starting a new scroll cancels the one in flight (its future
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

- Added animateScrollToKey: scroll to node by key.
- Various fixes and optimizations.

## 0.0.7

- Add SyncedTreeNode + new constructors.

## 0.0.6

- Refactor TreeMapView into SyncedSliverTree.

## 0.0.5

- test: add test for expansion memory during animated removal and re-addition.

## 0.0.4

- Fix expansion state for multi-sync.

## 0.0.3

- Fix expansion state history.

## 0.0.2

- Fix expanding a child node that has a collapsed parent (previously ignored expansion).
- Made child sync recursive for SyncedSliverTree and TreeSyncController.

## 0.0.1

- Adds sliver_tree: a node based sliver that supports tree-like nesting for data.
