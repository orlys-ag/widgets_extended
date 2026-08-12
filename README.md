# widgets_extended

A declarative, animated tree sliver for Flutter: **`SyncedSliverTree`**.

Hand it your data on every build. It diffs against what is on screen and
animates the difference: inserts grow in, removals shrink out, moves and
reorders slide, reparenting glides across depths. No controller to manage,
no imperative mutation calls, no manual keys bookkeeping. Drag-and-drop
reorder is one parameter.

## Quick start

```dart
import 'package:widgets_extended/widgets_extended.dart';

class Folder {
  Folder(this.id, this.name, [this.children = const []]);
  final String id;
  final String name;
  final List<Folder> children;
}
```

Your model already has the structure, so point the tree at it:

```dart
CustomScrollView(
  slivers: [
    SyncedSliverTree<String, Folder>.hierarchy(
      roots: folders,
      keyOf: (f) => f.id,
      childrenOf: (f) => f.children,
      indentWidth: 24,
      itemBuilder: (context, node) => ListTile(
        title: Text(node.item.name),
        leading: node.hasChildren
            ? Icon(node.isExpanded ? Icons.expand_more : Icons.chevron_right)
            : const Icon(Icons.insert_drive_file_outlined),
        onTap: node.toggle,
      ),
    ),
  ],
)
```

That is a working animated tree: tapping a row expands or collapses it with
animation, and rows indent by depth automatically (`indentWidth` pixels per
level).

To change the tree, change your data and hand in a **new list instance**:

```dart
setState(() {
  folders = folderStore.currentRoots(); // new instance = diff + animate
});
```

The widget diffs the new input against the screen and animates every
transition. Passing the `identical` instance as last time skips the diff
entirely (the `ListView.children` convention), so a frequently rebuilding
ancestor costs nothing. `keyOf` / `childrenOf` must be pure functions of
their argument.

## The row builder

`itemBuilder` receives a `TreeItemView` with everything a row usually needs,
all kept fresh automatically (rows rebuild when a sibling change shifts
them):

| | |
| --- | --- |
| Data | `node.item`, `node.key`, `node.depth`, `node.parentKey`, `node.indent` |
| Structure | `node.hasChildren`, `node.childCount`, `node.isFirst`, `node.isLast`, `node.indexInParent`, `node.siblingCount` |
| Expansion | `node.isExpanded`, `node.toggle()`, `node.expand()`, `node.collapse()` |

`node.isFirst` / `node.isLast` make connector lines and rounded-group
styling trivial. `node.controller` is the escape hatch to the full
imperative API if you ever need it.

## Drag-and-drop reorder

Pass a `reorder:` config. That is the whole integration:

```dart
SyncedSliverTree<String, Folder>.hierarchy(
  roots: folders,
  keyOf: (f) => f.id,
  childrenOf: (f) => f.children,
  indentWidth: 24,
  reorder: TreeReorderConfig<String>(
    onReorder: (key, newParent, index) {
      setState(() {
        folders = folderStore.move(key, toParent: newParent, at: index);
      });
    },
  ),
  itemBuilder: (context, node) => ListTile(title: Text(node.item.name)),
)
```

Every row becomes draggable by long-press, with no change to your builder.
While dragging, rows part to open a live gap at the prospective slot, a
floating proxy follows the pointer, hovering a collapsed parent auto-expands
it, the pointer's horizontal position picks the nesting depth at subtree
boundaries, and the drop settles in place with no jump.

Rules your `onReorder` handler lives by:

- **`index` is a final-list position.** Remove `key` from its old parent
  first, THEN insert at `index` in the new parent's children (`newParent`
  null means the root list). Computing an index against the pre-removal
  list puts same-parent downward moves one slot too far.
- **Your data stays authoritative.** A move you do not record is reverted
  by the next sync; that is also how you reject a drop. To roll back an
  already-recorded move, emit a NEW collection instance.
- **Async handlers record before awaiting**, then reconcile or roll back on
  the response.

To gate dragging per row, pass `canReorder: (key) => ...`. On desktop,
long-press reads as lag, so turn the default handles off and place a
visible grip anywhere inside the row (`TreeDragHandle` drags immediately,
`TreeDelayedDragHandle` on press-and-hold; both draw nothing):

```dart
reorder: TreeReorderConfig<String>(
  buildDefaultDragHandles: false,
  onReorder: ...,
),
itemBuilder: (context, node) => Row(
  children: <Widget>[
    Expanded(child: ListTile(title: Text(node.item.name))),
    TreeDragHandle(child: Icon(Icons.drag_indicator)),
  ],
),
```

Rows built from Material widgets need a `dragProxyBuilder` that re-provides
a `Material` ancestor (the proxy floats in the root `Overlay`, outside your
row's ancestry), the same contract as `Draggable.feedback`. Screen readers
get move up / down / out / into actions automatically, reported through the
same `onReorder`.

## Expansion

- `initiallyExpanded: true` (the default) opens the whole tree on first
  sync; `initialNodeExpansion: (key, item) => bool?` overrides it per node
  (return null to defer).
- `preserveExpansion: true` (the default) remembers expansion across
  remove/re-add cycles, and a user's deliberate collapse is never
  overridden by later syncs.
- `onExpansionChanged: (key, isExpanded) { ... }` is the hook for
  persisting expansion state.

For capabilities no row can reach, such as toolbar buttons or deep links,
grab the internal controller once:

```dart
SyncedSliverTree<String, Folder>.hierarchy(
  // ...
  onControllerCreated: (controller) => _tree = controller,
)

// Later:
_tree.expandAll();
_tree.animateScrollToKey(deepLinkedId, scrollController: scrollController);
```

Do not dispose it; the widget owns it.

## Other input modes

`.hierarchy` fits nested models. Two siblings cover the rest, with the same
parameters otherwise:

```dart
// Flat rows with parent pointers (query results, adjacency lists).
SyncedSliverTree<String, Row>.flat(
  items: rows,
  keyOf: (r) => r.id,
  parentOf: (r) => r.parentId, // null = root
  itemBuilder: ...,
)

// Explicit SyncedTreeNode tree, for when the UI itself edits structure.
SyncedSliverTree<String, Folder>(
  tree: [
    SyncedTreeNode(key: "docs", data: docs, children: [
      SyncedTreeNode(key: "taxes", data: taxes),
    ]),
  ],
  itemBuilder: ...,
)
```

## Animation styling

One `TreeAnimationStyle` times every animation family (expand/collapse,
enter/exit, reorder slides, the drag gap, drop settles). Defaults are 300ms
linear across the board:

```dart
SyncedSliverTree<String, Folder>.hierarchy(
  // ...
  animationStyle: TreeAnimationStyle.uniform(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
  ),
)
```

Per-family specs are available (`TreeAnimationStyle(expandCollapse: ...,
reorderSlide: ...)`), unset drag families inherit from `reorderSlide`, and
`TreeAnimationStyle.disabled` snaps everything, which is also the
synchronous-test configuration.

## Also in the box

- `maxStickyDepth: 1` pins root rows as sticky headers while scrolling
  through their children (higher values pin deeper levels too).
- `SectionedSliverList`: a two-level header + items convenience built on
  the same engine, with per-kind reorder config.
- `SliverTree` + `TreeController`: the imperative lowest layer, for full
  control over every mutation.

All of it runs on one sliver core: viewport-aware lazy building, dense
integer-indexed state storage, and reorder slides that are paint-only per
frame, so rows glide without relayout.
