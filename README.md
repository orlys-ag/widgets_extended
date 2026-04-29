# widgets_extended

High-performance sliver widgets for Flutter: animated tree, sectioned list, and drag-and-drop reorder.

- **`SectionedSliverList`** — header + items list with sticky headers, expand/collapse, and animated insert/remove.
- **`SyncedSliverTree`** — declarative tree that diffs against a source-of-truth and animates the transitions.
- **`SliverReorderableTree`** — drag-and-drop reorder layer on top of the tree.
- **`SliverTree` + `TreeController`** — imperative escape hatch.

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
  dropIndicatorColor: Colors.blue,
)
```

The `wrap(child:)` callback turns an arbitrary row into a draggable target with the framework-managed drop indicator.

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

`TreeController` exposes `addListener` (structure changes), `addAnimationListener` (animation ticks — no relayout), and `runBatch(...)` (coalesce mutations into one notification).
