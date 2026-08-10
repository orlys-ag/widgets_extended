# widgets_extended

High-performance sliver widgets for Flutter: animated tree, sectioned list, and drag-and-drop reorder.

- **`SectionedSliverList`**: header + items list with sticky headers, expand/collapse, and animated insert/remove.
- **`SyncedSliverTree`**: declarative tree that diffs against a source-of-truth and animates the transitions.
- **`SliverReorderableTree`**: drag-and-drop reorder layer on top of the tree.
- **`SliverTree` + `TreeController`**: imperative escape hatch.

All widgets are built on the same sliver/`TreeController` core: viewport-aware lazy layout, ECS-style state storage, animation finalization that doesn't relayout idle rows.

## SectionedSliverList

Header + items convenience sliver. Two constructor shapes:

```dart
// Declarative SectionInputs.
SectionedSliverList<String, String, Folder, FileItem>(
  sections: [
    SectionInput(
      key: folder.id,
      section: folder,
      items: [
        for (final f in folder.files) ItemInput(key: f.id, item: f),
      ],
    ),
    // ...
  ],
  headerBuilder: (context, view) => ListTile(
    title: Text("${view.section.name} (${view.itemCount})"),
    trailing: Icon(view.isExpanded ? Icons.expand_more : Icons.chevron_right),
    onTap: view.toggle,
  ),
  itemBuilder: (context, view) => ListTile(title: Text(view.item.name)),
  stickyHeaders: true,
  hideEmptySections: false,
  initiallyExpanded: true,
)
```

```dart
// groupListsBy-shaped: pass a Map<Section, List<Item>>.
SectionedSliverList<String, String, Folder, FileItem>.grouped(
  sections: groupedFolders, // Map<Folder, List<FileItem>>
  sectionKeyOf: (folder) => folder.id,
  itemKeyOf: (file) => file.id,
  headerBuilder: ...,
  itemBuilder: ...,
)
```

Pass a `SectionedListController` when you need imperative mutations (`addItem`, `removeSection`, `moveItem`, `runBatch`, ...). Without one, the widget owns its controller internally.

## SyncedSliverTree

Use `tree:` for the simplest entry point when you already have a nested immutable tree:

```dart
SyncedSliverTree<String, Folder>(
  tree: <SyncedTreeNode<String, Folder>>[
    SyncedTreeNode<String, Folder>(
      key: root.id,
      data: root,
      children: <SyncedTreeNode<String, Folder>>[
        SyncedTreeNode<String, Folder>(key: child.id, data: child),
      ],
    ),
  ],
  itemBuilder: (context, node) => ListTile(
    title: Text(node.item.name),
    leading: node.hasChildren
        ? IconButton(
            icon: Icon(node.isExpanded ? Icons.expand_more : Icons.chevron_right),
            onPressed: node.toggle,
          )
        : null,
  ),
)
```

There are three input modes, and they differ by where the tree's structure
lives:

- `.hierarchy(roots:, keyOf:, childrenOf:)` reads structure from your own
nested objects, and `.flat(items:, keyOf:, parentOf:)` from your own flat items
plus parent keys. Use these to display data you do not restructure in the UI:
you pass the collection you already hold, so no conversion step is involved.
- The default constructor keeps structure in a nested `SyncedTreeNode` tree.
Use it when the UI edits structure: your model owns parents and sibling
order, and you derive the tree input from it once per change.

```dart
SyncedSliverTree<String, RowData>(
  tree: viewModel.treeInput,
  itemBuilder: (context, node) => buildRow(node),
)
```

Every rebuild re-diffs against the mode's collection, and the diff is skipped
when you pass the `identical` instance as last time (the `ListView.children`
convention). Extractor callbacks are excluded from that check, so they must be
pure functions of their input.

## SliverReorderableTree

Wraps a `TreeController` with a `TreeReorderController` to add drag-and-drop reorder, including reparenting between branches:

```dart
SliverReorderableTree<String, RowData>(
  controller: treeController,
  reorderController: reorderController,
  nodeBuilder: (context, key, depth) => TreeDelayedDragHandle(
    child: ListTile(title: Text(treeController.getNodeData(key)!.data.label)),
  ),
)
```

Every row is wrapped for you, exactly as `SliverReorderableList` wraps every item, so `nodeBuilder` keeps the plain `SliverTree` signature. To make a row draggable by a pointer, put a `TreeDragHandle` (immediate, for a dedicated grip) or a `TreeDelayedDragHandle` (press-and-hold, safe around a whole row) somewhere inside it. Anywhere: a 32px bar across the top of a card, a leading grip, two of them. The package draws nothing and reserves no space.

A row with no handle cannot be lifted by a finger, but it is still a drop TARGET and still carries its reorder semantics actions.

Drop feedback is the make-room preview: rows part to open a live gap at the prospective slot (paint-only, so the tree is not mutated until the drop commits), while a floating proxy of the dragged row follows the pointer. The proxy renders in the root `Overlay`, outside the row's ancestry, so rows built from Material widgets need a `dragProxyBuilder` that re-provides a `Material` ancestor, the same contract as `Draggable.feedback`.

`indentWidth` maps the pointer's horizontal position to a drop depth at subtree boundaries. By default it reads the controller's own `indentWidth` (the constant rows actually render with), so the two agree with no configuration; set it explicitly when rows bake their own indent, or to `0` to always drop at the deepest legal level.

## Declarative reordering

`SyncedSliverTree` and `SectionedSliverList` reorder by configuring it. By default there is no change to your item builder: passing a config IS enabling the feature, and the package installs a long-press handle over each row, the way `ReorderableListView.buildDefaultDragHandles` does.

```dart
SyncedSliverTree<String, Folder>.hierarchy(
  roots: store.roots,
  keyOf: (f) => f.id,
  childrenOf: (f) => f.children,
  reorder: TreeReorderConfig<String>(
    onReorder: (key, newParent, index) {
      store.move(key, toParent: newParent, at: index);
    },
  ),
  itemBuilder: (context, view) => ListTile(title: Text(view.item.name)),
)
```

Rows long-press to drag on every platform. Desktop-targeted apps should turn the default off and place their own grip, because without one there is no visible affordance and a mouse long-press reads as lag:

```dart
reorder: TreeReorderConfig<String>(
  buildDefaultDragHandles: false,
  onReorder: ...,
),
itemBuilder: (context, view) => Row(
  children: <Widget>[
    Expanded(child: ListTile(title: Text(view.item.name))),
    TreeDragHandle(
      child: Icon(Icons.drag_indicator, color: Theme.of(context).hintColor),
    ),
  ],
),
```

Turning the default off leaves the row wrapped: it still hides itself while dragged, is still a drop target, and still carries its semantics actions. What it loses is the gesture, which the handle puts back wherever you put the handle. The package ships no grip of its own, because choosing one means choosing a foreground colour from a widgets-layer package that cannot see your background. There is no platform-adaptive default either; branch on `Theme.of(context).platform` in your own config if you want one, which honours an app's deliberate platform override where a `defaultTargetPlatform` read inside the package could not.

Pick one and keep it. `buildDefaultDragHandles` changes the row's widget shape, so flipping it at runtime re-inflates every row subtree and disposes the `State` your builder keeps there. `canReorder` is the runtime knob, and it is shaped to leave the row's structure untouched. For the same reason, prefer `TreeDragHandle(enabled: false)` to omitting a handle conditionally.

Something that must sit OUTSIDE the drag surface, such as a `Dismissible`, is now ordinary composition: `Dismissible(child: TreeDelayedDragHandle(child: row))`.

A refused row's handle stays visible and merely disarmed, because the package no longer decides what your grip looks like. To hide it while keeping its space and its inertness, read the policy back out of the scope:

```dart
Builder(
  builder: (context) {
    final canDrag = TreeRowDragScope.maybeOf(context)?.canDrag ?? false;
    return Visibility(
      visible: canDrag,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: TreeDragHandle(child: grip),
    );
  },
)
```

`Visibility`, not `Opacity(opacity: 0.0)`: `RenderOpacity` does not override `hitTest`, so a zero-alpha grip still swallows gestures.

`SectionedSliverList` takes a `SectionedReorderConfig`, where everything pairs by kind, because section and item keys share one type parameter and a single callback could not say which it was asked about. Items reorder by default and sections do not, and the default handles are per-kind too (`buildDefaultItemDragHandles` / `buildDefaultSectionDragHandles`). The module enforces its own two-level invariant (items only under sections, sections only at root, nothing under an item); a `canAccept*` callback can narrow that but never widen it.

### Four contracts that fail silently if you miss them

**The index is live-space and final-list.** It names the position among the destination's children AFTER the moved node is removed. Remove first, then insert at the reported index:

```dart
void onReorder(String key, String? newParent, int index) {
  // 1. Remove `key` from its old parent's child list (or the root list).
  // 2. THEN insert it at `index` in the new parent's list.
}
```

Computing your own index against the pre-removal list puts every same-parent downward move one slot too far, and cross-parent moves look fine, so it ships green.

**Not recording the move reverts it.** Your input collection stays authoritative, so a drop your handler ignores is undone by the next sync. That is the rejection mechanism, not a bug.

**Rollback needs a new collection instance.** Re-emitting the same reference is not observed, so a rejected move is never rolled back. Success is unaffected, which makes this an error-path-only trap.

**An async handler must record before awaiting.** The commit is optimistic only until the next sync, and you do not control when that is. Record optimistically, then reconcile or roll back on the response.

### Accessibility

Rows expose reorder actions to assistive technology automatically: move up, move down, move out, and move into previous sibling. Sectioned items additionally get move to previous and next section, because the two-level invariant would otherwise leave a screen-reader user unable to do something a pointer user can. All of them report through `onReorder` exactly as a drop does. `semanticsActionsBuilder` lets you add, remove or relabel actions; labels must be `const`, since `CustomSemanticsAction` interns identifiers with no removal path.

## SliverTree + TreeController (imperative)

The lowest layer. Build it directly when you want full control over insert/remove/expand/collapse timing:

```dart
final controller = TreeController<String, RowData>(vsync: this);
controller.setRoots([TreeNode(key: "root", data: root)]);
controller.expand(key: "root", animate: true);

CustomScrollView(slivers: [
  SliverTree<String, RowData>(
    controller: controller,
    nodeBuilder: (context, key, depth) => buildRow(controller.getNodeData(key)!.data),
  ),
])
```

`TreeController` exposes `addListener` (structure changes), `addAnimationListener` (animation ticks, no relayout), and `runBatch(...)` (coalesce mutations into one notification).

## Animation styling

One immutable `TreeAnimationStyle` configures timing and easing for every animation family, owned by the `TreeController` and inherited by everything downstream (the sync layer, the drag stack, and the declarative widgets via their `animationStyle` parameter):

| Family | Drives | Fallback |
| --- | --- | --- |
| `expandCollapse` | expand/collapse groups, `expandAll`/`collapseAll`, sync-driven slide cohesion | none |
| `enterExit` | insert/remove row animations | `expandCollapse` |
| `reorderSlide` | FLIP slides: `moveNode`, `reorderRoots`/`reorderChildren`, drag-commit | none |
| `makeRoom` | the drag make-room gap (open / re-target / release) | `reorderSlide` |
| `dropSettle` | drag proxy settle glides (commit handoff, cancel return) | `reorderSlide` |

```dart
final controller = TreeController<String, RowData>(
  vsync: this,
  animationStyle: const TreeAnimationStyle(
    expandCollapse: TreeAnimationSpec(
      duration: Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    ),
    reorderSlide: TreeAnimationSpec(
      duration: Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    ),
    // enterExit / makeRoom / dropSettle inherit when unset.
  ),
);
```

Rules of the system:

- **Defaults are uniform**: every family defaults to 300ms / `Curves.linear` (`TreeAnimationStyle.defaultSpec`). `TreeAnimationStyle.uniform(duration:, curve:)` builds a one-spec-everywhere style.
- **Per-call overrides win** for value selection: `moveNode`, `reorderRoots`/`reorderChildren`, `animateSlideFromOffsets`, and the preview methods take optional `Duration`/`Curve` params that beat the style when passed.
- **Zero is a per-family kill switch**: a family whose resolved spec has `Duration.zero` duration snaps instead of animating, and that dominates explicit per-call durations. `TreeAnimationStyle.disabled` zeroes every family, which is the synchronous-test configuration.
- **Runtime restyle** is a plain assignment (`controller.animationStyle = ...`). Duration changes rewrite in-flight expand/collapse groups (they finish at their old rate; the new duration applies from the next start), curves apply to newly started groups, and enter/exit animations re-read the style every tick. Drag sessions resolve the style once at `startDrag`, so a mid-drag restyle applies from the next drag.
- Unset fallback families keep **inheriting**: `copyWith` preserves their unset-ness, so restyling `reorderSlide` also retimes an unset `makeRoom`/`dropSettle`.
