/// Input normalization for [SyncedSliverTree]'s input modes.
///
/// Each mode's raw input (a nested [SyncedTreeNode] tree, nested domain
/// objects, or flat items plus parent keys) is walked ONCE into a
/// [NormalizedTreeInput]: [TreeNode] lists in render order, ready to feed
/// `TreeSyncController.syncRoots`. Validation happens during the walk and
/// throws [ArgumentError] naming the offending key, so a malformed input
/// is rejected before any controller state is touched. There is no second
/// validation layer behind these walks; each normalizer must reject every
/// malformed shape on its own, in every build mode.
///
/// Underscore-prefixed file: not exported by the barrel. Class and
/// function names are public so tests can import this file directly, the
/// same convention as `_drag_session.dart`.
library;

import 'synced_tree_node.dart';
import 'types.dart';

/// Immutable-by-convention normalized tree structure consumed by
/// `SyncedSliverTree`'s sync pass.
///
/// [roots] defines root order and [childrenByParent] stores sibling order
/// for each parent, both as fully-built [TreeNode]s so the sync layer
/// never re-materializes them.
class NormalizedTreeInput<TKey, TItem> {
  const NormalizedTreeInput({
    required this.roots,
    required this.childrenByParent,
  });

  final List<TreeNode<TKey, TItem>> roots;
  final Map<TKey, List<TreeNode<TKey, TItem>>> childrenByParent;

  List<TreeNode<TKey, TItem>> childrenOf(TKey key) {
    return childrenByParent[key] ?? <TreeNode<TKey, TItem>>[];
  }
}

/// Normalizes a nested [SyncedTreeNode] tree (the default constructor's
/// input mode).
NormalizedTreeInput<TKey, TItem> normalizeSyncedNodes<TKey, TItem>(
  Iterable<SyncedTreeNode<TKey, TItem>> tree,
) {
  final roots = <TreeNode<TKey, TItem>>[];
  final childrenByParent = <TKey, List<TreeNode<TKey, TItem>>>{};
  final seen = <TKey>{};
  final visiting = <TKey>{};
  // Iterative DFS so deep input trees do not stack-overflow Dart's
  // recursion limit. Tracks each node's [TreeNode] in [nodeByKey] so
  // the post-order exit phase can populate `childrenByParent[key]`
  // by looking up each child's already-built [TreeNode]; sidesteps
  // the recursive version's "visit child returns its TreeNode for the
  // parent's list" pattern.
  final nodeByKey = <TKey, TreeNode<TKey, TItem>>{};

  final stack = <SyncedTreeNode<TKey, TItem>>[];
  final isRootStack = <bool>[];
  // true = post-order exit frame, false = pre-order entry frame.
  final exitMarkers = <bool>[];

  // Push roots in reverse so the first root pops first, preserving
  // input order; same trick as the children push below.
  final rootList = tree is List<SyncedTreeNode<TKey, TItem>>
      ? tree
      : tree.toList(growable: false);
  for (int i = rootList.length - 1; i >= 0; i--) {
    stack.add(rootList[i]);
    isRootStack.add(true);
    exitMarkers.add(false);
  }

  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    final isRoot = isRootStack.removeLast();
    final isExit = exitMarkers.removeLast();

    if (isExit) {
      visiting.remove(node.key);
      if (node.children.isNotEmpty) {
        final childNodes = <TreeNode<TKey, TItem>>[];
        for (final child in node.children) {
          childNodes.add(nodeByKey[child.key]!);
        }
        childrenByParent[node.key] = childNodes;
      }
      continue;
    }

    final key = node.key;
    if (!visiting.add(key)) {
      throw ArgumentError(
        "SyncedSliverTree.tree detected a cycle involving key \"$key\".",
      );
    }
    if (!seen.add(key)) {
      throw ArgumentError(
        "SyncedSliverTree.tree encountered duplicate key \"$key\".",
      );
    }

    // Pre-validate sibling-key uniqueness within node.children. Done
    // before the recursion so the error matches the recursive version's
    // throw site (parent context, not deep inside the child's visit).
    final seenChildren = <TKey>{};
    for (final child in node.children) {
      if (!seenChildren.add(child.key)) {
        throw ArgumentError(
          "SyncedSliverTree.tree encountered duplicate child key "
          "\"${child.key}\" under parent \"$key\".",
        );
      }
    }

    final treeNode = TreeNode<TKey, TItem>(key: key, data: node.data);
    nodeByKey[key] = treeNode;
    if (isRoot) {
      roots.add(treeNode);
    }

    // Push exit marker FIRST so it pops AFTER all children; the
    // recursive version's `visiting.remove(key)` and its
    // `childrenByParent[key] = childNodes` happen at the tail of the
    // function body, after all child recursion completes.
    stack.add(node);
    isRootStack.add(false);
    exitMarkers.add(true);

    // Then push children in reverse so the first child pops first,
    // preserving left-to-right visit order.
    for (int i = node.children.length - 1; i >= 0; i--) {
      stack.add(node.children[i]);
      isRootStack.add(false);
      exitMarkers.add(false);
    }
  }

  return NormalizedTreeInput<TKey, TItem>(
    roots: roots,
    childrenByParent: childrenByParent,
  );
}

/// Normalizes nested domain objects (the `.hierarchy` input mode).
///
/// The walk itself establishes every invariant on the way past: cycles
/// via [visiting], global key uniqueness via the `nodeByKey` guard (which
/// is also what rejects a node under two parents, and a root that
/// reappears as a child), sibling uniqueness via `seenChildren`, and
/// reachability by construction, since every emitted node was reached by
/// the DFS.
NormalizedTreeInput<TKey, TItem> normalizeHierarchy<TKey, TItem>({
  required Iterable<TItem> roots,
  required TKey Function(TItem item) keyOf,
  required Iterable<TItem> Function(TItem item) childrenOf,
}) {
  final rootNodes = <TreeNode<TKey, TItem>>[];
  final childrenByParent = <TKey, List<TreeNode<TKey, TItem>>>{};
  final nodeByKey = <TKey, TreeNode<TKey, TItem>>{};
  final visiting = <TKey>{};

  // Iterative DFS so deep hierarchies do not stack-overflow Dart's
  // recursion limit. Three parallel stacks: `items` holds the work
  // queue; `exitMarkers` mirrors it as `null` for entry frames or as
  // the key whose `visiting` slot must be cleared on exit (post-order);
  // `exitChildKeys` carries each exit frame's child keys so the exit pop
  // can assemble `childrenByParent` from the children's already-built
  // [TreeNode]s. Exit frames push and pop in matching LIFO order, so the
  // two exit stacks stay aligned.
  final items = <TItem>[];
  final isRootStack = <bool>[];
  final exitMarkers = <TKey?>[];
  final exitChildKeys = <List<TKey>>[];

  // Push roots in REVERSE so the first root pops first. `items` is a
  // LIFO stack, so seeding it forward reversed the whole root list in
  // the output while child order (pushed in reverse below) stayed
  // correct. Same trick, same reason, as the children loop.
  final rootList = roots is List<TItem> ? roots : roots.toList(growable: false);
  for (int i = rootList.length - 1; i >= 0; i--) {
    items.add(rootList[i]);
    isRootStack.add(true);
    exitMarkers.add(null);
  }

  while (items.isNotEmpty) {
    final item = items.removeLast();
    final isRoot = isRootStack.removeLast();
    final exitKey = exitMarkers.removeLast();

    if (exitKey != null) {
      // Post-order pop: leaving this key's subtree, whose children have
      // all been built by now.
      visiting.remove(exitKey);
      final childKeys = exitChildKeys.removeLast();
      if (childKeys.isNotEmpty) {
        childrenByParent[exitKey] = <TreeNode<TKey, TItem>>[
          for (final childKey in childKeys) nodeByKey[childKey]!,
        ];
      }
      continue;
    }

    final key = keyOf(item);
    if (!visiting.add(key)) {
      throw ArgumentError(
        "SyncedSliverTree.hierarchy detected a cycle involving key "
        "\"$key\".",
      );
    }
    if (nodeByKey.containsKey(key)) {
      throw ArgumentError(
        "SyncedSliverTree.hierarchy encountered duplicate key \"$key\".",
      );
    }

    final treeNode = TreeNode<TKey, TItem>(key: key, data: item);
    nodeByKey[key] = treeNode;
    if (isRoot) {
      rootNodes.add(treeNode);
    }

    final childKeys = <TKey>[];
    final seenChildren = <TKey>{};
    // Resolve children once so we can both record their keys and push
    // them in the correct visit order (last-pushed = first-popped).
    final childItems = <TItem>[];
    for (final child in childrenOf(item)) {
      final childKey = keyOf(child);
      if (!seenChildren.add(childKey)) {
        throw ArgumentError(
          "SyncedSliverTree.hierarchy encountered duplicate child key "
          "\"$childKey\" under parent \"$key\".",
        );
      }
      childKeys.add(childKey);
      childItems.add(child);
    }

    // Push exit marker FIRST so it pops AFTER all children; preserves
    // the recursive version's `visiting.remove(key)` placement at the
    // tail of the function body.
    items.add(item); // placeholder, ignored on exit pop
    isRootStack.add(false);
    exitMarkers.add(key);
    exitChildKeys.add(childKeys);

    // Then push children in reverse so the first child pops first,
    // matching the recursive version's left-to-right visit order.
    for (int i = childItems.length - 1; i >= 0; i--) {
      items.add(childItems[i]);
      isRootStack.add(false);
      exitMarkers.add(null);
    }
  }

  return NormalizedTreeInput<TKey, TItem>(
    roots: rootNodes,
    childrenByParent: childrenByParent,
  );
}

/// Normalizes flat items plus parent keys (the `.flat` input mode).
///
/// Sibling order follows the iteration order of [items]. If [parentOf]
/// returns a key that is not present in [items], the item is treated as a
/// root.
NormalizedTreeInput<TKey, TItem> normalizeFlat<TKey, TItem>({
  required Iterable<TItem> items,
  required TKey Function(TItem item) keyOf,
  required TKey? Function(TItem item) parentOf,
}) {
  final orderedItems = List<TItem>.of(items);
  final nodeByKey = <TKey, TreeNode<TKey, TItem>>{};

  for (final item in orderedItems) {
    final key = keyOf(item);
    if (nodeByKey.containsKey(key)) {
      throw ArgumentError(
        "SyncedSliverTree.flat encountered duplicate key \"$key\".",
      );
    }
    nodeByKey[key] = TreeNode<TKey, TItem>(key: key, data: item);
  }

  final rootNodes = <TreeNode<TKey, TItem>>[];
  final childrenByParent = <TKey, List<TreeNode<TKey, TItem>>>{};
  for (final item in orderedItems) {
    final key = keyOf(item);
    final parentKey = parentOf(item);
    final TKey? effectiveParent =
        parentKey != null && nodeByKey.containsKey(parentKey)
        ? parentKey
        : null;

    if (effectiveParent == null) {
      rootNodes.add(nodeByKey[key]!);
    } else {
      final children = childrenByParent.putIfAbsent(
        effectiveParent,
        () => <TreeNode<TKey, TItem>>[],
      );
      children.add(nodeByKey[key]!);
    }
  }

  // Reachability. Unlike the DFS-based normalizers, the two-pass build
  // above cannot establish it by construction: a mutual parent cycle
  // (`a` claims `b` as parent while `b` claims `a`) yields nodes that
  // hang under each other with no path from any root, and without this
  // walk they would silently never render. Iterative for the same
  // deep-input reason as the DFS walks.
  final reached = <TKey>{};
  final stack = <TKey>[for (final root in rootNodes) root.key];
  while (stack.isNotEmpty) {
    final key = stack.removeLast();
    if (!reached.add(key)) {
      continue;
    }
    final children = childrenByParent[key];
    if (children != null) {
      for (final child in children) {
        stack.add(child.key);
      }
    }
  }
  if (reached.length != nodeByKey.length) {
    final unreachable = <TKey>[
      for (final key in nodeByKey.keys)
        if (!reached.contains(key)) key,
    ];
    throw ArgumentError(
      "SyncedSliverTree.flat contains unreachable nodes (a parent "
      "cycle): $unreachable.",
    );
  }

  return NormalizedTreeInput<TKey, TItem>(
    roots: rootNodes,
    childrenByParent: childrenByParent,
  );
}
