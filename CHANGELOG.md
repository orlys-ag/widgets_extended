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
