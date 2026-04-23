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
