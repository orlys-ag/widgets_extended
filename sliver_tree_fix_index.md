# sliver_tree fix plan: implementer's index

Companion to `sliver_tree_fix_plan.md`, derived from it. The units below
are the connected components of that document's dependency chains, and
every effort rating and test name is read out of the block it belongs
to. If the two ever disagree, the plan is right and this index is stale;
regenerate rather than hand-edit.

## How to use it

BEFORE trusting any file:line in a block, read the plan's section
"Line citations are stale in the working tree". Items have landed
without being committed, so most body citations into the files they
touched now point at the wrong line. Re-derive by grepping the named
symbol. That section carries the measured per-file counts; they are
deliberately not repeated here, so there is one number to maintain.

Pick ONE unit and read only the blocks it names. No CHAIN crosses a unit
boundary, so units can be taken in any order and by different people.
Before running two units in parallel, check the adjacency list below:
that is the one interaction units do not capture, because those pairs
have no required order and so do not merge into a unit.

Inside a unit the stated order is a constraint, not a preference: the
plan says, for each pairing, what breaks if it lands the other way. Two
pairings have no shippable intermediate at all and must go in a single
commit; those are marked ONE COMMIT.

Effort is the plan's own rating: S under a day, M a day or two, L more
than that or needs a maintainer decision.

[DONE] means the block carries a Status line saying it has landed;
[NOT AUDITED] means the block was filed after the readiness audit
finished, so unlike the other items it has NOT been through three
clean passes and its Solution may still carry an open decision. Read
its Status line before scheduling it.
[PARTLY DONE] means some sub-items landed and the rest are open, in
which case the block says which. Both are read out of the plan, so a
missing marker means the plan does not claim the work is done.

Measured: 58 items in 34 units, being 7 coupled clusters plus 27 items
with no chain. 18 chains in total, of which 2 require a single commit
(chains 1 and 15), plus 4 adjacency pairs that constrain nothing but should
not be worked in parallel. The plan creates 13 new test files.

Landed so far: 21 implemented (H2, H4, H6, L6, L7, L24, L27, M1, M2, M3, M4, M5, M6, M7, M8, M9, M14, M16, M21, M22, M23); 2 partially implemented
(L25, L26). Everything else is open.

## Coupled clusters

### Cluster 1: H1, H2, H3, L6, L7, L13, L24, L25, M6, M7, M8, M10, M20

- **H1** (L) Scroll position is never corrected for estimate vs measured row height
- **H2** (M) Admission starves the viewport below a row taller than the cache extent  **[DONE]**
- **H3** (M) `animateScrollToKey` after a mutation clamps to the pre-layout `maxScrollExtent`
- **L6** (M) `applyPaintTransform` has no branch for anchor-based exit ghosts  **[DONE]**
- **L7** (S) Pass A's edge-ghost skip must ask the FLIP-only question  **[DONE]**
- **L13** (S) Make every scroll the orchestrator starts single-flight, both directions
- **L24** (M) Pass A.7 repaints an exit-ghost anchor a second time per frame  **[DONE]**
- **L25** (M) Minor render-layer and buffer performance items  **[PARTLY DONE]**
- **M6** (S) The bulk-only fast path falls off on every frame  **[DONE]**
- **M7** (S) Paint-extent loop reads unwritten per-nid slots on bulk frames  **[DONE]**
- **M8** (L) Bulk `collapseAll` never admits rows after the collapsing subtree  **[DONE]**
- **M10** (M) Exit-ghost lifecycle reads the anchor's composed delta
- **M20** (M) `animateScrollToKey` ignores the sticky band

Ordering constraints:

- Chain 1, bulk extents and admission (M6, then M7, then M8, with H2).  **ONE COMMIT**
- Chain 3, exit-ghost pipeline (M10, then L6, L7 and L24).
- Chain 5, scroll targeting (H1, then H3, then M20).
- Chain 11, admission sub-items (L25.4 and L25.6 with M8).
- Chain 14, the resolve guard and the plain-path session (H3 with L13).
- Chain 16, the sticky force-create loop (M7, then H1).
- Chain 17, the measurement loop (M8, then H1).
- Chain 18, the carve-out inventory (H1 with M10), no fixed order.

New tests: `audit_repro_h1_test.dart`, `audit_repro_h3_test.dart`, `scroll_sticky_inset_test.dart`.

Existing tests touched: `adjacent_collapsed_exit_ghost_test.dart`, `animated_move_to_test.dart`, `animation_transitions_test.dart`, `audit_repro_f24_test.dart`, `audit_repro_h2_test.dart`, `bounded_iteration_test.dart`, `bulk_collapse_admission_test.dart`, `bulk_fast_path_stability_test.dart`, `bulk_paint_extent_test.dart`, `bulk_reentry_continuation_test.dart`, `bulk_sticky_recompute_test.dart`, `cache_extent_protocol_test.dart`, `concurrent_extents_test.dart`, `entry_phantom_clip_unchanged_test.dart`, `exit_ghost_prune_flip_only_test.dart`, `find_row_after_bulk_test.dart`, `find_row_stale_cache_test.dart`, `findrow_bounded_scan_oracle_test.dart`, `ghost_flip_only_pass_a_skip_test.dart`, `ghost_prune_flip_only_test.dart`, `ghost_revisible_double_paint_test.dart`, `independent_timelines_test.dart`, `layout_admission_policy_test.dart`, `live_index_oracle_fuzz_test.dart`, `make_room_offcache_build_test.dart`, `mid_slide_eviction_test.dart`, `offscreen_anchor_exit_ghost_test.dart`, `paint_purity_test.dart`, `parent_data_refresh_iteration_test.dart`, `phantom_anchor_reparent_test.dart`, `phantom_anchor_staging_test.dart`, `phantom_exit_reparent_test.dart`, `preview_eviction_test.dart`, `purge_subtree_visible_size_test.dart`, `purge_visible_subtree_size_test.dart`, `rapid_reparent_visual_gaps_test.dart`, `rebuild_budget_test.dart`, `remove_contiguous_fast_path_test.dart`, `remove_from_order_zombie_leak_test.dart`, `render_host_registry_test.dart`, `repaint_boundary_test.dart`, `reparent_all_gap_test.dart`, `reparent_painted_coverage_test.dart`, `repro_occlusion_tall_card_test.dart`, `scroll_orchestrator_dispose_test.dart`, `scroll_orchestrator_position_swap_test.dart`, `scroll_reresolve_test.dart`, `slide_paint_only_test.dart`, `slide_scroll_concurrency_test.dart`, `slide_viewport_clamp_test.dart`, `sliver_tree_widget_test.dart`, `sticky_bulk_stale_offset_test.dart`, `sticky_entering_root_handover_test.dart`, `sticky_offcache_cumulative_perf_test.dart`, `sticky_small_tree_max_paint_test.dart`, `synced_on_controller_created_test.dart`, `tall_card_occlusion_zorder_test.dart`, `visible_order_buffer_test.dart`, `visible_subtree_size_invariant_fuzz_test.dart`.

### Cluster 2: H4, L27, M1, M2, M5

- **H4** (M) Depth-limited `expandAll` / `collapseAll` ignore post-flip visibility  **[DONE]**
- **L27** (M) Bulk reversals re-target op-group envelopes without the Path-1 rebase  **[DONE]**
- **M1** (S) Re-insert of a mid-exit node under a collapsed parent leaves a permanent row  **[DONE]**
- **M2** (M) Re-inserting a mid-exit node keeps its old subtree  **[DONE]**
- **M5** (L) Standalone animations spawned by expand/collapse are timed by `enterExit`  **[DONE]**

Ordering constraints:

- Chain 8, the THREE blocks that rewrite `_cancelDeletion` (M1, then M2, then
M5).
- Chain 12, blocks that change the `_startStandalone*` install-site set (M5
with H4 and L27).
- Chain 15, the op-group reversal bodies (H4 with L27), ONE commit.  **ONE COMMIT**

Existing tests touched: `animation_notify_coalescing_test.dart`, `animation_style_flow_test.dart`, `animation_style_test.dart`, `animation_transitions_test.dart`, `audit_repro_h4_test.dart`, `audit_repro_m2_test.dart`, `audit_repro_m5_test.dart`, `bulk_dispose_generation_test.dart`, `bulk_reentry_continuation_test.dart`, `child_count_invalidation_test.dart`, `collapsed_interior_fallback_test.dart`, `concurrent_extents_test.dart`, `dismissed_handler_mixed_category_test.dart`, `drop_zone_resolver_test.dart`, `expand_all_interior_expanded_test.dart`, `expand_collapse_all_stale_order_test.dart`, `expand_collapse_staging_gate_test.dart`, `findrow_bounded_scan_oracle_test.dart`, `ghost_prune_flip_only_test.dart`, `imperative_remove_with_mirror_test.dart`, `independent_timelines_test.dart`, `live_index_oracle_fuzz_test.dart`, `op_group_iteration_snapshot_test.dart`, `purge_cache_audit_test.dart`, `purge_subtree_visible_size_test.dart`, `readd_pending_deletion_test.dart`, `remove_flushes_visible_order_test.dart`, `reparent_during_exit_test.dart`, `section_header_item_count_test.dart`, `skip_repro_test.dart`, `tree_controller_test.dart`, `tree_expansion_listener_test.dart`, `tree_sync_controller_test.dart`, `unmeasured_exit_extent_test.dart`, `visible_subtree_size_invariant_fuzz_test.dart`.

### Cluster 3: H6, L26, M14

- **H6** (S) Inherited-widget reads in `nodeBuilder` never refresh rows  **[DONE]**
- **L26** (M) Housekeeping the house rules forbid  **[PARTLY DONE]**
- **M14** (S) `forgetChild` drops the render box, then the framework drops it again  **[DONE]**

Ordering constraints:

- Chain 10, comment fixes that depend on their code change (L26 with H6 and
M14).

Adjacent to items outside this cluster (see the adjacency list): L26 with H5.

Existing tests touched: `audit_repro_h6_test.dart`, `audit_repro_m14_test.dart`, `child_count_invalidation_test.dart`, `controller_swap_children_retained_test.dart`, `controller_swap_test.dart`, `data_only_reinsert_notification_test.dart`, `drag_proxy_test.dart`, `mid_slide_eviction_test.dart`, `parent_data_refresh_iteration_test.dart`, `sliver_tree_widget_test.dart`, `source_encoding_guard_test.dart`, `sticky_nid_recycle_test.dart`, `tree_node_builder_targeted_rebuild_test.dart`.

### Cluster 4: M4, M9, M21

- **M4** (M) Comparator re-insert of an existing key moves it one slot right  **[DONE]**
- **M9** (M) K inserts under one parent cost O(K * S)  **[DONE]**
- **M21** (S) Same-parent relocation notifies only the moved key  **[DONE]**

Ordering constraints:

- Chain 2, sibling refresh (M9 before M21).
- Chain 13, the relocation helper and its notification (M4 with M21).

Adjacent to items outside this cluster (see the adjacency list): M9 with M16.

Existing tests touched: `audit_repro_m4_test.dart`, `batch_notification_test.dart`, `child_count_invalidation_test.dart`, `data_only_reinsert_notification_test.dart`, `insert_after_move_in_batch_test.dart`, `insert_relocation_sibling_refresh_test.dart`, `live_index_cache_test.dart`, `live_index_oracle_fuzz_test.dart`, `rebuild_budget_test.dart`, `sibling_position_freshness_test.dart`, `sibling_refresh_batching_test.dart`, `tree_controller_test.dart`, `tree_node_builder_targeted_rebuild_test.dart`, `tree_reorder_controller_test.dart`, `tree_sync_controller_test.dart`.

### Cluster 5: L2, M12, M13

- **L2** (S) Delete the dead `remaining.insert` on the `syncChildren` path
- **M12** (M) `syncRoots` computes root insert indices before deferred removals
- **M13** (M) `syncRoots` lacks the mover-subtree deferral

Ordering constraints:

- Chain 7, the sync diff (M12 and M13 are one change).
- Chain 9, the sync diff's `remaining` list (M12 with L2).

New tests: `audit_repro_m12_test.dart`, `audit_repro_m13_test.dart`.

Existing tests touched: `audit_repro_f32_test.dart`, `audit_repro_f33_test.dart`, `batch_notification_test.dart`, `reparent_during_exit_test.dart`, `skip_repro_test.dart`, `sync_children_of_memoization_test.dart`, `sync_controller_truth_test.dart`, `sync_deferral_during_drag_test.dart`, `sync_expansion_memory_regression_test.dart`, `sync_multiple_children_subtree_test.dart`, `synced_reorder_e2e_test.dart`, `synced_reorder_test.dart`, `synced_sliver_tree_test.dart`, `tree_sync_controller_test.dart`, `tree_sync_deep_tree_test.dart`, `unmeasured_exit_extent_test.dart`.

### Cluster 6: H5, M19

- **H5** (L) A `GlobalKey` inside a row breaks dragging
- **M19** (M) `Opacity(1.0)` around every reorderable row

Ordering constraints:

- Chain 4, the drag proxy and the hidden row (H5 with M19).

Adjacent to items outside this cluster (see the adjacency list): H5 with L26.

New tests: `audit_repro_h5_test.dart`, `reorder_row_layer_and_focus_test.dart`.

Existing tests touched: `caller_placed_handle_modes_test.dart`, `caller_placed_handle_test.dart`, `can_reorder_flip_mid_drag_test.dart`, `drag_backstop_deactivate_test.dart`, `drag_handle_audit_test.dart`, `drag_handle_hidden_test.dart`, `drag_proxy_indent_tracking_test.dart`, `drag_proxy_move_rebuild_test.dart`, `drag_proxy_test.dart`, `drag_subtree_hide_test.dart`, `drag_subtree_proxy_test.dart`, `external_cancel_drag_test.dart`, `hidden_row_hit_test.dart`, `policy_flip_preserves_row_state_test.dart`, `reorder_controller_disposed_swap_test.dart`, `reorder_controller_swap_mid_drag_test.dart`, `reorder_enabled_toggle_test.dart`, `repaint_boundary_test.dart`, `sliver_reorderable_tree_widget_test.dart`, `synced_reorder_test.dart`.

### Cluster 7: L21, M11

- **L21** (M) A drag started on a sticky-pinned header probes the content beneath the strip
- **M11** (M) The hidden dragged row shadows rows the preview shifted into its band

Ordering constraints:

- Chain 6, drag row lookup (M11 before L21).

New tests: `audit_repro_m11_test.dart`.

Existing tests touched: `auto_expand_dwell_test.dart`, `below_zone_expanded_parent_test.dart`, `drag_proxy_test.dart`, `drag_session_unit_test.dart`, `drag_subtree_hide_test.dart`, `findrow_bounded_scan_oracle_test.dart`, `gap_anchor_resolved_slot_test.dart`, `hidden_row_hit_test.dart`, `make_room_hole_commit_test.dart`, `make_room_preview_test.dart`, `preview_eviction_test.dart`, `reorder_commit_path_test.dart`, `reorder_render_port_test.dart`, `reorder_tuning_liveness_test.dart`, `sticky_grab_geometry_test.dart`, `sticky_root_diff_repro_test.dart`, `touch_probe_test.dart`, `x_aware_below_zone_test.dart`.

## Adjacent, but not ordered

These pairs edit the same method or file at disjoint statements.
Neither order breaks anything, so they are not chains and they do
not merge their units. They are listed because scheduling them in
parallel invites a merge conflict, and in one case the first to land
moves the other's line anchors. Quoted from the plan's Sequencing
section:

- **M3 with M23**, `expand` Path 2. M3 replaces the mixed body at `tree_controller.dart:3865-3897`; M23 wraps the `forward()` two lines later at `:3899-3900`. Membership is identical under either body (both skip `_isPendingDeletion` before joining the group), so M23's emptiness guard reads the same answer. But M3 shrinks the preceding body from about 33 lines to about 13, so if M3 lands first, M23's line anchors move and must be re-derived. M23's block already warns that its anchors are fragile; this is the specific reason.

- **M9 with M16**, `moveNode`'s single `affected` block. M16 rewrites the depth branch at `tree_controller.dart:3627-3633`; M9 renames the two `_siblingRefreshSet` calls at `:3636-3637`. Semantically independent: M16 changes which keys the depth branch contributes, M9 changes when the sibling set is materialized. Adjacent lines, so expect a merge conflict, not a bug.

- **M17 with M25**, `PointerSpace.sample` (`_drag_session.dart:79-97`). M25 inserts a `syncScrollSubscription()` call at the prologue and deletes `DragSession.subscribeScroll` (`:299-320`); M17 replaces the `sliverX` expression at `:89`. Disjoint statements, neither reads state the other establishes.

- **H5 with L26**, `sliver_reorderable_tree.dart`. L26's ASCII pass rewrites comment bytes across the file and one string literal at `:735`; H5 rewrites `:1031-1033` and two dartdoc paragraphs. Disjoint, but a whole-file byte pass over a file another item is editing is worth knowing about.

## Items with no chain

No CHAIN constrains these against anything else. A (+) marks an item
that appears in the adjacency list above: still free to land in any
order, but do not hand it and its partner to two people at once without
reading that entry first.

| Item | Effort | What it fixes | New test | Adjacent to | Status |
| --- | --- | --- | --- | --- | --- |
| L1 | S | Skip order compaction when the removed batch held no visible slot | - | - | - |
| L3 | M | Route `setChildren` through the buffer's removal owners and flush first | - | - | - |
| L4 | S | Make the four key-existence guards throw in release too | `mutator_unknown_key_guard_test.dart` | - | - |
| L5 | S | `animateSlideFromOffsets` null-check on an unregistered key | - | - | - |
| L8 | S | Make `snapshotSettledVisibleOffsets` lazy at the consume site | - | - | - |
| L9 | M | O(1) preview overreach bound via a maintained high-water mark | `reorder_preview_max_delta_test.dart` | - | - |
| L10 | S | Delete the nine dead members | - | - | - |
| L11 | S | Drop the two internal exports from the barrel | - | - | - |
| L12 | S | `insertRoot`/`insert` must not gate `moveNode` on the `enterExit` kill switch | - | - | - |
| L14 | M | Expansion memory on the direct `syncChildren` path is never consumed or pruned | - | - | - |
| L15 | M | Gained-children heuristic can override a collapse made during the last child's exit | - | - | - |
| L16 | S | syncMultipleChildren rejects duplicate keys only under `assert`, so release builds mutate before they refuse | - | - | - |
| L17 | S | startDrag does not re-check _session after cancelDrag | - | - | - |
| L18 | S | startDrag accepts a pending-deletion or unknown key | - | - | - |
| L19 | S | _applyMove returns the unclamped index on the cross-parent path | - | - | - |
| L20 | S | Autoscroll ticker keeps scheduling frames while parked at an extent | - | - | - |
| L22 | S | DropSettler's cancel/fallback glide double-counts an in-flight FLIP | - | - | - |
| L23 | S | Sticky-classified rows never show a FLIP slide | - | - | - |
| L28 | M | Direction flip under a same-frame pending baseline drops the edge-to-edge composition | - | - | - |
| L29 | M | Optional: capture InheritedTheme for the drag proxy | - | - | - |
| M3 (+) | M | `expand(animate: false)` mid-collapse misorders new descendants | - | M23 | [DONE] |
| M16 (+) | S | `moveNode` depth change does not dirty rows hidden under a collapsed node | - | M9 | [DONE] |
| M17 (+) | M | Drag proxy is sized and positioned in the viewport's cross-axis frame | `audit_repro_m17_test.dart` | M25 | - |
| M22 | S | `expand` Path 1 leaves the animating mirror stale | - | - | [DONE] |
| M23 (+) | M | Empty operation-group shells keep `hasActiveAnimations` true | - | M3 | [DONE] |
| M25 (+) | M | Scroll subscription bound to the `ScrollPosition` captured at `startDrag` | `drag_position_swap_test.dart` | M17 | - |
| M26 | S | Hot reload does not refresh rows when the `SliverTree` instance is hoisted | `audit_repro_m26_test.dart` | - | [NOT AUDITED] |

