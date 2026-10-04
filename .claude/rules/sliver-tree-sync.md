---
paths:
  - "lib/sliver_tree/tree_sync_controller.dart"
  - "lib/sliver_tree/synced_sliver_tree.dart"
  - "lib/sliver_tree/_synced_input_normalizer.dart"
  - "lib/sliver_tree/_sync_helpers.dart"
  - "lib/sliver_tree/synced_tree_node.dart"
  - "lib/sliver_tree/tree_node_builder.dart"
  - "lib/sliver_tree/_deferred_sync_gate.dart"
---

# sliver_tree architecture: sync layer

The contract of `TreeSyncController`, `SyncedSliverTree` and `TreeNodeBuilder`. The conventions every layer follows are in `sliver-tree.md`.

- **TreeSyncController** (`tree_sync_controller.dart`): Diffing layer on top of TreeController. Diffs the desired state against **controller truth** (`liveRootKeys`/`getLiveChildren`; there is no private tracking mirror), so direct controller mutations (escape hatch, drag-drop commits) compose safely with syncs. Preserves expansion state across remove/re-add cycles, defers cross-parent movers, validates cycles/duplicate keys in `childrenOf`, and exact-match early-outs per parent.
- **SyncedSliverTree** (`synced_sliver_tree.dart`): Declarative widget owning both controllers internally; three input modes (tree/hierarchy/flat). Input normalization and its validation live in `_synced_input_normalizer.dart` (public names, barrel non-exported). Skips the re-diff when mode inputs are `identical` across rebuilds (pass new collection instances to signal change). The auto-expand heuristic (`_sync_helpers.dart`) never overrides a user's deliberate collapse (expansion memory + emptied-while-collapsed suppression).
- **TreeNodeBuilder** (`tree_node_builder.dart`): Selective-rebuild widget that only rebuilds when a specific node's `hasChildren` or `isExpanded` state changes.
