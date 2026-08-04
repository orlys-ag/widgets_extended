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
  headerBuilder: (context, view) => view.watch(
    builder: (ctx, v) => ListTile(
      title: Text(v.section.name),
      trailing: Icon(v.isExpanded ? Icons.expand_more : Icons.chevron_right),
      onTap: v.toggle,
    ),
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

Use `.nodes(...)` when your data already exists as roots plus `childrenOf(key)`:

```dart
SyncedSliverTree<String, RowData>.nodes(
  roots: viewModel.roots,
  childrenOf: viewModel.childrenOf,
  itemBuilder: (context, node) => buildRow(node),
)
```

`SyncedSliverTree` also supports `.hierarchy(...)`, `.flat(...)`, and `.snapshot(...)` for other source-data shapes.

## SliverReorderableTree

Wraps a `TreeController` with a `TreeReorderController` to add drag-and-drop reorder, including reparenting between branches:

```dart
SliverReorderableTree<String, RowData>(
  controller: treeController,
  reorderController: reorderController,
  nodeBuilder: (context, key, depth, wrap) => wrap(
    child: ListTile(title: Text(treeController.getNodeData(key)!.data.label)),
  ),
  indentPerDepth: 24.0,
)
```

The `wrap(child:)` callback turns an arbitrary row into a draggable target. Drop feedback is the make-room preview: rows part to open a live gap at the prospective slot (paint-only, so the tree is not mutated until the drop commits), while a floating proxy of the dragged row follows the pointer. The proxy renders in the root `Overlay`, outside the row's ancestry, so rows built from Material widgets need a `dragProxyBuilder` that re-provides a `Material` ancestor, the same contract as `Draggable.feedback`.

`indentPerDepth` maps the pointer's horizontal position to a drop depth at subtree boundaries; set it to `0` to always drop at the deepest legal level.

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
