---
paths:
  - "lib/sliver_tree/*.dart"
  - "lib/sliver_tree/**/*.dart"
  - "lib/sectioned_sliver_list/*.dart"
  - "lib/sectioned_sliver_list/**/*.dart"
  - "test/sliver_tree/*.dart"
  - "test/sliver_tree/**/*.dart"
  - "test/sectioned_sliver_list/*.dart"
  - "test/sectioned_sliver_list/**/*.dart"
---

# sliver_tree architecture

Normative for `lib/sliver_tree/` and for `lib/sectioned_sliver_list/`, which adapts the sliver_tree stack and so follows its contract. This rule holds the conventions every layer follows; each layer's contract is in the rule that names its files:

| Rule | Covers |
|---|---|
| `sliver-tree-core.md` | `types.dart`, `NodeStore`, `VisibleOrderBuffer`, `TreeController`, `RenderSliverTree`, `SliverTreeElement` and `SliverTree` |
| `sliver-tree-animation.md` | `AnimationCoordinator`, its sources, and the carve-out accessors with their read sites |
| `sliver-tree-reorder.md` | `TreeReorderController` and `SliverReorderableTree` |
| `sliver-tree-sync.md` | `TreeSyncController`, `SyncedSliverTree` and `TreeNodeBuilder` |

No layer rule names the files of `lib/sectioned_sliver_list/` or the barrel `sliver_tree.dart`: for them, read `sliver-tree-core.md` and `sliver-tree-sync.md`, and for the sectioned files that import the reorder layer, `sliver-tree-reorder.md`.

## Conventions that cut across every layer

- **nids (ECS-style storage).** Every key is assigned a dense integer node id (`NodeIdRegistry`, LIFO free list; nids are recycled). All per-node state lives in dense nid-indexed arrays (`Int32List`/`Float64List`/`Uint8List`) grown in lockstep via `onCapacityGrew`. Hot paths use `*Nid` method variants to avoid key hashing.
- **Live-space index contract.** Every public `index` parameter (`insert`, `insertRoot`, `moveNode`) and every read-side index API (`getIndexInParent`, `liveRootKeys`, `getLiveChildren`, `reorderRoots`/`reorderChildren` validation) speaks **live space**: positions among non-pending-deletion siblings. Exiting (mid-remove) siblings are skipped. Conversion to the raw sibling lists happens once at the write boundary (`_liveIndexToFullInsertIndex`). `getIndexInParent` is O(1) amortized via a generation-validated cache (`_live_index_cache.dart`): every raw-sibling-list-mutating method calls `_liveIndexCache.bump()` AFTER its write clusters (exit placement is load-bearing, user comparators read mid-mutation; see the component doc), pending-deletion flips bump via the two controller forwarders, and a new mutator must add its bump AND join the oracle fuzz's script (`live_index_oracle_fuzz_test.dart`).
- **Two notification channels.** Structural changes fire `addStructuralListener(Set<TKey>? affectedKeys)` (null = full refresh, empty = handled by create/GC, non-empty = exactly these rows may differ); pure data updates fire `addNodeDataListener(TKey)`. `affectedKeys` covers any change to a row's *rendered* inputs (data, depth, raw child-list length, and live child count; pending-deletion marking dirties the parent), not only `hasChildren` flips. Structural subsumes data; never fire both for one row. A third channel, `addAnimationListener`, ticks per frame during animations (coalesced to one dispatch per frame; the slide engine's settle notify is deliberately uncoalesced).
- **Coordinate spaces.** Three distinct spaces, and mixing them produces errors that are invisible while scrolled to the top:
  - **Sliver scroll space** ("sliver-local"): distance from the start of the tree sliver's scroll extent, first row at 0. This is the `ReorderRenderPort` contract (`findRowAtPaintedY`, `beginSlideBaseline`, `TreeDropTarget.targetPaintedY`/`targetExtent`) and what `SliverTreeParentData.layoutOffset` stores.
  - **Sliver paint space**: sliver scroll space minus `constraints.scrollOffset`. Used by paint, clipping, hit-testing, and `_anchorPaintedBounds`.
  - **Viewport scroll space**: sliver scroll space plus `constraints.precedingScrollExtent`. Consumers subtract `position.pixels` to reach viewport-local. `TreeDropTarget` carries no viewport-space field of its own; presentation layers derive one from the semantic target plus `ReorderRenderPort.precedingScrollExtent`.
- **Declare an animation's family ONCE, at the boundary.** Every code path that installs an animation decides its `TreeAnimationStyle` family at exactly one named site; the install call that resolves its spec and computes its kill-switch flag (`animateSlideFromOffsets` = reorderSlide; `animateDropSettleGlide` = dropSettle; the preview methods = makeRoom; mutator gates = expandCollapse/enterExit; the two standalone installers, `_startStandaloneEnterAnimation` and `_startStandaloneExitAnimation`, take a required `family` argument that is stored on the `AnimationState` and resolved through `TreeAnimationStyle.specFor` at tick time, so a mutator's partial reversals and nested exits run on the mutator's family, not on `enterExit`). Downstream code (engine, render, collaborators) never re-derives family membership. A new consumer whose family differs from the API it rides gets an internal-use-only channel (house precedent: `animateDropSettleGlide`), never a public flag parameter.

## Usage patterns

- **Imperative**: Create `TreeController` with a `TickerProviderStateMixin`, call `setRoots`/`setChildren`/`insert`/`remove`/`expand`/`collapse` directly, wrap in `SliverTree`.
- **Declarative diffing**: Use `SyncedSliverTree` with one of its three input modes.
- **Manual sync**: Use `TreeSyncController` with `syncRoots`/`syncChildren`/`syncMultipleChildren` for custom sync logic.
- **Drag-and-drop**: Use `SliverReorderableTree` with a shared `TreeReorderController`; every row from `nodeBuilder` is wrapped for reorder unconditionally.

## sectioned_sliver_list

`SectionedListController<K, Section, Item>` adapts the sliver_tree stack to a two-level sections/items model using wrapped keys (`SectionKey`/`ItemKey`). Item keys must be globally unique across sections (sync-time validation rejects duplicates). The widget layer mirrors `SyncedSliverTree`'s declarative shape.
