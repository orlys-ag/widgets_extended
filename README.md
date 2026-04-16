# widgets_extended

Utility widgets for Flutter, including a declarative sliver tree with animated syncing.

## SyncedSliverTree

Use `tree:` for the simplest entry point when you already have a nested immutable tree:

```dart
SyncedSliverTree<String, Folder>(
  tree: <SyncedTreeNode<String, Folder>>[
    SyncedTreeNode<String, Folder>(
      key: root.id,
      data: root,
      children: <SyncedTreeNode<String, Folder>>[
        SyncedTreeNode<String, Folder>(
          key: child.id,
          data: child,
        ),
      ],
    ),
  ],
  itemBuilder: (context, node) {
    return ListTile(
      title: Text(node.item.name),
      leading: node.hasChildren
          ? IconButton(
              icon: Icon(
                node.isExpanded
                    ? Icons.expand_more
                    : Icons.chevron_right,
              ),
              onPressed: node.toggle,
            )
          : null,
    );
  },
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
