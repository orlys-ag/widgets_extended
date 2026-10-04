---
paths:
  - "lib/sliver_tree/types.dart"
  - "lib/sliver_tree/_node_store.dart"
  - "lib/sliver_tree/_node_id_registry.dart"
  - "lib/sliver_tree/_visible_order_buffer.dart"
  - "lib/sliver_tree/tree_controller.dart"
  - "lib/sliver_tree/_tree_controller_animation.dart"
  - "lib/sliver_tree/_tree_controller_helpers.dart"
  - "lib/sliver_tree/animation_style.dart"
  - "lib/sliver_tree/_scroll_orchestrator.dart"
  - "lib/sliver_tree/_live_index_cache.dart"
  - "lib/sliver_tree/render_sliver_tree.dart"
  - "lib/sliver_tree/sliver_tree_element.dart"
  - "lib/sliver_tree/sliver_tree_widget.dart"
  - "lib/sliver_tree/_layout_admission_policy.dart"
  - "lib/sliver_tree/_sticky_header_computer.dart"
  - "lib/sliver_tree/_slide_composer.dart"
  - "lib/sliver_tree/_slide_baseline_slot.dart"
  - "lib/sliver_tree/_ghost_registry.dart"
  - "lib/sliver_tree/_viewport_snapshot.dart"
---

# sliver_tree architecture: core

The contract of `types.dart`, `NodeStore`, `VisibleOrderBuffer`, `TreeController`, `RenderSliverTree`, `SliverTreeElement` and `SliverTree`. The conventions every layer follows are in `sliver-tree.md`.

- **types.dart**: Shared types: `TreeNode<TKey, TData>`, `AnimationState`, `SlideAnimation`, `AnimationGroup`, `OperationGroup`, `BulkAnimationData`, `SliverTreeParentData`, `StickyHeaderInfo`.
- **NodeStore** (`_node_store.dart`): Structural component store: the `NodeIdRegistry` plus dense per-nid arrays for data, parent, children, depth, expansion, and the ancestors-expanded cache. Fires `onParentChanged` on every `setParent`.
- **VisibleOrderBuffer** (`_visible_order_buffer.dart`): The flattened visible order as a dense nid array + reverse index + visible-subtree-size cache (O(1) `subtreeSizeOf`, O(depth) `bumpFromSelf`). Bulk protocols are owned by intention-revealing methods (`rebuild`, `removeContiguousRange`, `purgeCompact`, `reindexFrom`); raw views are read-only for hot paths. Suppression (`runWithSubtreeSizeUpdatesSuppressed`) lets callers pre-bump the cache and batch compactions.
- **TreeController** (`tree_controller.dart` + part files `_tree_controller_animation.dart`, `_tree_controller_helpers.dart`): Central state manager tying store + order + animations together. Animation timing/easing lives in ONE immutable `TreeAnimationStyle` (`animation_style.dart`, mutable `animationStyle` property): five families, `expandCollapse` (op groups, bulk, the animated-concurrent scroll gate), `enterExit` (inherits expandCollapse), `reorderSlide` (all FLIP slides), `makeRoom`/`dropSettle` (inherits reorderSlide). Uniform defaults 300ms/`Curves.linear` (`TreeAnimationStyle.defaultSpec`). Per-family zero is a KILL SWITCH that dominates explicit per-call durations (`TreeAnimationStyle.disabled` = everything off; there is no master switch). The zero rule is SPLIT: a zero family CREATES no motion (installs refused; other families' in-flight slides survive and re-base across concurrent mutations), while DISABLING (restyling `reorderSlide` to zero) STOPS in-flight slide motion at the transition (`SlideAnimationEngine.purgeActive`, called from the `animationStyle` setter). Per-call `Duration?`/`Curve?` params on `moveNode`/`reorderRoots`/`reorderChildren`/`animateSlideFromOffsets`/the preview methods resolve null to family spec. Sync-layer moves/reorders pass `expandCollapse` explicitly for same-batch cohesion. Mutators (`setRoots`/`setChildren`/`insert`/`insertRoot`/`remove`/`moveNode`/`expand`/`collapse`/`expandAll`/`collapseAll`/`reorderRoots`/`reorderChildren`), `runBatch` (defers order rebuild + notifications to batch exit; mutators flush via `_ensureVisibleOrder` on entry), and the **ScrollOrchestrator** (`_scroll_orchestrator.dart`: `animateScrollToKey` immediate/animated modes, full-extent prefix cache; every scroll it starts is single-flight in both directions; a scroll issued during animations rides the concurrent follower and waits for quiescence, and a not-yet-laid-out mutation costs one frame's wait instead of a clamp to stale `maxScrollExtent`; landings are re-derived by a post-frame settle snap, paired with the render object's anchor-preserving `scrollOffsetCorrection`; `avoidStickyHeaders` insets the target below the sticky band its pinned ancestors will form, `stickyInsetOf` exposes the same number; cancellation wired through `dispose`). Inserting/moving under a pending-deletion parent throws `StateError` in all build modes.
- **RenderSliverTree** (`render_sliver_tree.dart`): Custom `RenderSliver`: viewport-aware layout (cache-region admission via `LayoutAdmissionPolicy`, bulk-only cumulative fast path), paint passes (static rows, sliding rows by |delta|, exit ghosts, edge ghosts, header repaint, sticky), hit-testing that matches paint z-order during slides, sticky headers via `StickyHeaderComputer`, and the slide pipeline. FLIP slides consume a staged baseline (`SlideComposer` = `SlideBaselineSlot` (first-wins) + `GhostRegistry` (edge ghosts)); exit ghosts are consolidated `_ExitGhost` records (anchor, slidUp, edge XOR clipped). Paint/hit-test/semantics iteration is viewport-bounded; slide-only ticks are paint-only (layout runs on install/settle, and on a tick whose `composedSlideAbsDeltaBound` exceeds the `admittedSlideBound` the last layout recorded, which is how a make-room preview's shifted rows get built). Rows are wrapped in `RepaintBoundary` by default (`addRepaintBoundaries`).
- **SliverTreeElement** (`sliver_tree_element.dart`): Custom element implementing `TreeChildManager`: lazy child creation during layout callbacks, dirty-key targeted rebuilds (a hot reload queues every mounted row for the same in-place refresh in both ancestor shapes; nothing recreates rows on reload), dead-node GC and post-frame stale eviction (gated on FLIP slides, not the composed flag; respects `isNodeRetained`: pins, sticky, ghosts, mid-FLIP rows).
- **SliverTree** (`sliver_tree_widget.dart`): The core `RenderObjectWidget`. Takes a `TreeController` and a `nodeBuilder`.
