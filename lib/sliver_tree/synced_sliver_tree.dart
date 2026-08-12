/// A declarative sliver tree with data-first input modes.
///
/// [SyncedSliverTree] owns both a [TreeController] and a [TreeSyncController]
/// internally. Callers provide domain data through one of three input shapes,
/// which differ by where the tree's STRUCTURE lives:
///
/// - [SyncedSliverTree.hierarchy] reads structure from your own nested
///   objects, and [SyncedSliverTree.flat] from your own flat items plus
///   parent keys. Use these to display data you do not restructure in the UI.
/// - [SyncedSliverTree.new] keeps structure in a nested [SyncedTreeNode]
///   tree. Use it when the UI edits structure.
///
/// The widget diffs the normalized tree on rebuild and applies animated
/// insertions, removals, and reparenting.
library;

import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart';

import '_deferred_sync_gate.dart';
import '_sync_helpers.dart';
import '_synced_input_normalizer.dart';
import 'animation_style.dart';
import 'sliver_reorderable_tree.dart';
import 'tree_drag_handle.dart';
import 'tree_reorder_config.dart';
import 'tree_reorder_controller.dart';
import 'sliver_tree_widget.dart';
import 'synced_tree_node.dart';
import 'tree_controller.dart';
import 'tree_sync_controller.dart';

/// Builds a widget for a visible synced tree node.
typedef TreeItemBuilder<TKey, TItem> =
    Widget Function(BuildContext context, TreeItemView<TKey, TItem> node);

enum _SyncedSliverTreeMode { tree, hierarchy, flat }

/// Rich view of a visible synced tree node passed to [itemBuilder].
class TreeItemView<TKey, TItem> {
  const TreeItemView({
    required this.key,
    required this.item,
    required this.depth,
    required this.parentKey,
    required this.controller,
  });

  /// Unique identifier for this node.
  final TKey key;

  /// User payload for this node.
  final TItem item;

  /// Nesting depth (0 for roots).
  final int depth;

  /// Parent node key, or null when this node is a root.
  final TKey? parentKey;

  /// The backing tree controller.
  ///
  /// Most callers should rely on the richer convenience properties on this
  /// view, but the controller remains available as an escape hatch.
  final TreeController<TKey, TItem> controller;

  /// Whether this node is a root.
  bool get isRoot {
    return parentKey == null;
  }

  /// Position among this node's siblings, 0-based, in **live space**:
  /// siblings that are animating out are skipped.
  ///
  /// Returns -1 while this node is itself animating out.
  int get indexInParent {
    return controller.getIndexInParent(key);
  }

  /// How many siblings this node sits among, itself included, excluding
  /// siblings that are animating out.
  ///
  /// Deliberately live-space, matching [indexInParent]: the two are meant
  /// to be read together (`indexInParent == siblingCount - 1`), and pairing
  /// a live index with a count that includes exiting rows would report the
  /// wrong last row for the length of every removal animation.
  int get siblingCount {
    final parent = parentKey;
    if (parent == null) {
      return controller.liveRootCount;
    }
    return controller.liveChildCount(parent);
  }

  /// Whether this node is the first of its live siblings.
  ///
  /// Useful for connector lines, dividers and rounded-group styling. Rows
  /// are rebuilt when a sibling insert, removal, reorder or move shifts
  /// their position, so this stays fresh without any extra subscription.
  bool get isFirst {
    return indexInParent == 0;
  }

  /// Whether this node is the last of its live siblings. See [isFirst].
  bool get isLast {
    final index = indexInParent;
    return index >= 0 && index == siblingCount - 1;
  }

  /// Horizontal indent for this node in logical pixels.
  double get indent {
    return controller.getIndent(key);
  }

  /// Whether this node currently has children.
  bool get hasChildren {
    return controller.hasChildren(key);
  }

  /// Number of direct children currently attached to this node.
  ///
  /// Includes children that are still animating out after a removal:
  /// during an exit animation the departing rows are still painted, and
  /// this count matches them. Use [liveChildCount] for the settled count.
  int get childCount {
    return controller.getChildCount(key);
  }

  /// Number of direct children excluding those animating out.
  ///
  /// Prefer [childCount] for a count rendered alongside the children
  /// themselves: during an exit animation the departing rows are still
  /// painted, and [childCount] matches them. Use this when the count
  /// should describe the settled state instead.
  int get liveChildCount {
    return controller.liveChildCount(key);
  }

  /// Whether this node has children that are not animating out.
  bool get hasLiveChildren {
    return controller.hasLiveChildren(key);
  }

  /// Whether this node is currently expanded.
  bool get isExpanded {
    return controller.isExpanded(key);
  }

  /// Expands this node.
  void expand({bool animate = true}) {
    controller.expand(key: key, animate: animate);
  }

  /// Collapses this node.
  void collapse({bool animate = true}) {
    controller.collapse(key: key, animate: animate);
  }

  /// Toggles this node between expanded and collapsed.
  void toggle({bool animate = true}) {
    controller.toggle(key: key, animate: animate);
  }
}

/// The reorder pair, created together or not at all.
///
/// Exists so that "reorder is on" is ONE nullable value rather than two
/// that have to agree. Two independently nullable fields is exactly the
/// shape that let `build` dispatch on the controller and then dereference
/// the config, which is a crash the type system can rule out instead.
class _ReorderRuntime<TKey> {
  const _ReorderRuntime({
    required this.controller,
    required this.initialConfig,
  });

  final TreeReorderController<TKey> controller;

  /// The config as supplied at construction.
  ///
  /// Only a FALLBACK: live reads go through `widget.reorder` first, so a
  /// caller's edits to the config's contents still take effect on the
  /// next rebuild. This covers the unsupported case where the config's
  /// presence itself changes, which `didUpdateWidget` asserts against.
  final TreeReorderConfig<TKey> initialConfig;
}

/// A sliver widget that declaratively displays a tree and animates changes.
///
/// Example:
/// ```dart
/// SyncedSliverTree<String, Folder>(
///   tree: <SyncedTreeNode<String, Folder>>[
///     SyncedTreeNode<String, Folder>(
///       key: rootFolder.id,
///       data: rootFolder,
///       children: <SyncedTreeNode<String, Folder>>[
///         SyncedTreeNode<String, Folder>(
///           key: childFolder.id,
///           data: childFolder,
///         ),
///       ],
///     ),
///   ],
///   itemBuilder: (context, node) {
///     return ListTile(
///       title: Text(node.item.name),
///       leading: node.hasChildren
///           ? IconButton(
///               icon: Icon(
///                 node.isExpanded
///                     ? Icons.expand_more
///                     : Icons.chevron_right,
///               ),
///               onPressed: node.toggle,
///             )
///           : null,
///     );
///   },
/// )
/// ```
///
/// ## Rebuild convention
///
/// Every rebuild re-diffs the tree against this widget's input collection.
/// To keep an ancestor that rebuilds frequently from paying that O(N) walk
/// for nothing, the diff is skipped when the collection is the `identical`
/// instance passed on the previous build. This is the same convention as
/// [ListView.children]: mutating a collection in place is not observed;
/// pass a new instance to signal a change.
///
/// The extractor callbacks (`keyOf`, `childrenOf`, `parentOf`) are
/// deliberately NOT part of that check: inline lambdas are a fresh
/// closure instance on every build and would defeat it entirely. They must
/// be pure functions of their input; a semantic change to one is picked up
/// on the next sync where the collection instance also changes.
class SyncedSliverTree<TKey, TItem> extends StatefulWidget {
  /// Creates a synced sliver tree from an immutable nested tree.
  ///
  /// Rebuilds re-diff only when [tree] is a different instance than the
  /// previous build's. See "Rebuild convention" on [SyncedSliverTree].
  const SyncedSliverTree({
    required Iterable<SyncedTreeNode<TKey, TItem>> tree,
    required this.itemBuilder,
    this.preserveExpansion = true,
    this.initiallyExpanded = true,
    this.animationStyle = const TreeAnimationStyle(),
    this.indentWidth = 0.0,
    this.maxStickyDepth = 0,
    this.addRepaintBoundaries = true,
    this.maxExpansionMemorySize = 1024,
    this.initialNodeExpansion,
    this.onControllerCreated,
    this.onExpansionChanged,
    this.reorder,
    super.key,
  }) : _mode = _SyncedSliverTreeMode.tree,
       _tree = tree,
       _hierarchyRoots = null,
       _flatItems = null,
       _keyOf = null,
       _childrenOf = null,
       _parentOf = null;

  /// Creates a synced sliver tree from nested domain objects.
  ///
  /// Rebuilds re-diff only when [roots] is a different instance than the
  /// previous build's; [keyOf] and [childrenOf] must be pure functions of
  /// their input. See "Rebuild convention" on [SyncedSliverTree].
  const SyncedSliverTree.hierarchy({
    required Iterable<TItem> roots,
    required TKey Function(TItem item) keyOf,
    required Iterable<TItem> Function(TItem item) childrenOf,
    required this.itemBuilder,
    this.preserveExpansion = true,
    this.initiallyExpanded = true,
    this.animationStyle = const TreeAnimationStyle(),
    this.indentWidth = 0.0,
    this.maxStickyDepth = 0,
    this.addRepaintBoundaries = true,
    this.maxExpansionMemorySize = 1024,
    this.initialNodeExpansion,
    this.onControllerCreated,
    this.onExpansionChanged,
    this.reorder,
    super.key,
  }) : _mode = _SyncedSliverTreeMode.hierarchy,
       _tree = null,
       _hierarchyRoots = roots,
       _flatItems = null,
       _keyOf = keyOf,
       _childrenOf = childrenOf,
       _parentOf = null;

  /// Creates a synced sliver tree from flat items with optional parent keys.
  ///
  /// Rebuilds re-diff only when [items] is a different instance than the
  /// previous build's; [keyOf] and [parentOf] must be pure functions of
  /// their input. See "Rebuild convention" on [SyncedSliverTree].
  const SyncedSliverTree.flat({
    required Iterable<TItem> items,
    required TKey Function(TItem item) keyOf,
    required TKey? Function(TItem item) parentOf,
    required this.itemBuilder,
    this.preserveExpansion = true,
    this.initiallyExpanded = true,
    this.animationStyle = const TreeAnimationStyle(),
    this.indentWidth = 0.0,
    this.maxStickyDepth = 0,
    this.addRepaintBoundaries = true,
    this.maxExpansionMemorySize = 1024,
    this.initialNodeExpansion,
    this.onControllerCreated,
    this.onExpansionChanged,
    this.reorder,
    super.key,
  }) : _mode = _SyncedSliverTreeMode.flat,
       _tree = null,
       _hierarchyRoots = null,
       _flatItems = items,
       _keyOf = keyOf,
       _childrenOf = null,
       _parentOf = parentOf;

  final _SyncedSliverTreeMode _mode;
  final Iterable<SyncedTreeNode<TKey, TItem>>? _tree;
  final Iterable<TItem>? _hierarchyRoots;
  final Iterable<TItem>? _flatItems;
  final TKey Function(TItem item)? _keyOf;
  final Iterable<TItem> Function(TItem item)? _childrenOf;
  final TKey? Function(TItem item)? _parentOf;

  /// Builds the widget for each visible node.
  final TreeItemBuilder<TKey, TItem> itemBuilder;

  /// Whether to preserve expansion state when nodes are removed and re-added.
  final bool preserveExpansion;

  /// Whether nodes should be expanded when they first appear.
  ///
  /// Applies to the whole tree on the first sync, and to nodes that gain
  /// their first children in a later sync. [initialNodeExpansion] overrides
  /// it per node.
  final bool initiallyExpanded;

  /// Per-node initial-expansion policy, consulted for each node when it
  /// first appears: on the first sync for the whole tree, and afterwards
  /// for nodes that are new in a sync or that gain their first children.
  ///
  /// Return true to expand, false to leave collapsed, or null to defer to
  /// [initiallyExpanded]. Null (the default) applies [initiallyExpanded]
  /// to every node.
  ///
  /// A node's own expansion state always wins over this policy once it
  /// exists: this is an INITIAL policy, so later user toggles are never
  /// overridden, and a node removed and re-added while
  /// [preserveExpansion] is on comes back with its remembered state rather
  /// than the policy's answer.
  ///
  /// Must be a pure function of its inputs. Like the other callbacks it is
  /// excluded from the rebuild identity check (see "Rebuild convention"),
  /// so a changed policy takes effect on the next sync that runs, applied
  /// to the nodes appearing in it.
  final bool? Function(TKey key, TItem item)? initialNodeExpansion;

  /// Animation timing/easing for every family, forwarded to the
  /// internal [TreeController.animationStyle].
  final TreeAnimationStyle animationStyle;

  /// Horizontal indent per depth level in logical pixels.
  final double indentWidth;

  /// How many depth levels of headers should stick to the top.
  ///
  /// 0 means no sticky headers. 1 means root nodes stick, etc.
  final int maxStickyDepth;

  /// Whether to wrap each row in a [RepaintBoundary]. Forwarded to
  /// [SliverTree.addRepaintBoundaries].
  final bool addRepaintBoundaries;

  /// Maximum number of nodes whose expansion state is remembered across
  /// remove/re-add cycles. Forwarded to
  /// [TreeSyncController.maxExpansionMemorySize].
  ///
  /// Only consulted when [preserveExpansion] is true. Setting 0 disables
  /// expansion memory entirely; every observable effect of
  /// [preserveExpansion] flows through that memory, so 0 is equivalent to
  /// `preserveExpansion: false`. Changing this value rebuilds the
  /// internal sync controller, which discards whatever it had remembered
  /// so far.
  final int maxExpansionMemorySize;

  /// Called once with the internal [TreeController], right after the first
  /// sync and the initial expansion pass, so the controller is already in
  /// its settled initial state.
  ///
  /// This is the supported way to reach controller capabilities that no
  /// row builder can offer: [TreeController.animateScrollToKey], toolbar
  /// `expandAll` / `collapseAll`, reading expansion state to persist it.
  ///
  /// The reference is valid until this widget's [State] disposes; do NOT
  /// dispose it yourself, and do not call `setState` synchronously from
  /// this callback (it runs during `initState`); store the reference and
  /// use it from later callbacks.
  ///
  /// Imperative structural mutations through this controller are legal and
  /// compose with syncing, but this widget's input collection stays
  /// authoritative: the next sync diffs against it and reverts structural
  /// drift.
  final void Function(TreeController<TKey, TItem> controller)?
  onControllerCreated;

  /// Called whenever a node's expansion state changes, with the node's key
  /// and its new state.
  ///
  /// Fires for user-driven toggles, imperative calls through the
  /// controller, and sync-driven expansion alike. The intended use is
  /// persisting expansion state; a caller that wants only deliberate user
  /// gestures should report those from its own row callbacks instead.
  ///
  /// Two silences are deliberate. This widget's own initial expansion pass
  /// does not fire (it is initialization, and a consumer restoring
  /// persisted state would otherwise be told to overwrite it), and neither
  /// does the flag reset that comes with a node being created or removed
  /// (see [TreeController.addExpansionListener]).
  final void Function(TKey key, bool isExpanded)? onExpansionChanged;

  /// Enables drag-and-drop reorder. Null disables it at zero cost.
  ///
  /// Non-null is all that is required: by default rows become draggable
  /// with no change to [itemBuilder], because
  /// [TreeReorderConfig.buildDefaultDragHandles] installs a long-press
  /// handle over each row. Set it false to place [TreeDragHandle]s
  /// yourself. See [TreeReorderConfig].
  ///
  /// Whether this is null is fixed for the widget's lifetime. Swapping
  /// between null and non-null would change the widget type at this slot,
  /// tearing down the sliver, its per-key child caches and its render
  /// object, and would orphan a live drag session. To toggle reorder at
  /// runtime keep the config and flip [TreeReorderConfig.enabled].
  final TreeReorderConfig<TKey>? reorder;

  @override
  State<SyncedSliverTree<TKey, TItem>> createState() =>
      _SyncedSliverTreeState<TKey, TItem>();
}

class _SyncedSliverTreeState<TKey, TItem>
    extends State<SyncedSliverTree<TKey, TItem>>
    with TickerProviderStateMixin {
  late TreeController<TKey, TItem> _treeController;
  late TreeSyncController<TKey, TItem> _syncController;
  bool _hasSyncedOnce = false;

  /// Reorder state, created iff reorder was enabled at construction.
  ///
  /// The controller and the config it was built from live and die
  /// TOGETHER in one nullable field, which is the whole point: no code
  /// path can hold one without the other, so `build` needs no `!` on
  /// either. The crash this replaced is not guarded against, it is
  /// unrepresentable.
  ///
  /// What it replaced: `build` dispatched on the controller alone, which
  /// only covers a null to non-null flip. In the other direction the
  /// controller exists, so `build` went on to `widget.reorder!` and a
  /// RELEASE build threw `Null check operator used on a null value` from
  /// inside `build` -- debug being saved only by `didUpdateWidget`'s
  /// presence assert firing first. Every forwarder's "a null config
  /// degrades to refusing" reasoning was moot, because the widget had
  /// already crashed before any of them could be asked.
  ///
  /// Worth saying plainly: no test pins this. `flutter_test` runs with
  /// asserts enabled, so `didUpdateWidget` aborts the subtree build first
  /// and a test behaves identically either way (verified, not assumed).
  /// Making the state unrepresentable is the substitute for the test that
  /// cannot be written.
  _ReorderRuntime<TKey>? _reorderRuntime;

  /// Holds a structural diff while a drag is live. Built iff
  /// [_reorderRuntime] is (reorder cannot be added or removed after
  /// construction; see the assert in [didUpdateWidget]), so every use is
  /// null-guarded the same way [_reorderRuntime]'s are.
  DeferredSyncGate<TKey>? _syncGate;

  @override
  void initState() {
    super.initState();
    _treeController = TreeController<TKey, TItem>(
      vsync: this,
      animationStyle: widget.animationStyle,
      indentWidth: widget.indentWidth,
    );
    final initialReorder = widget.reorder;
    if (initialReorder != null) {
      _reorderRuntime = _ReorderRuntime<TKey>(
        controller: TreeReorderController<TKey>(
          treeController: _treeController,
          vsync: this,
          // Stable forwarders, built once. The controller's policy fields
          // are final and its resolver captures them on first use, so the
          // config cannot be read through `widget` at use time; and an
          // inline closure in the caller's config would otherwise churn.
          canReorder: _handleCanReorder,
          canAcceptDrop: _handleCanAcceptDrop,
          onReorder: _handleReorder,
          autoExpandDelay: initialReorder.autoExpandDelay,
          autoScrollEdgeZone: initialReorder.autoScrollEdgeZone,
          autoScrollMaxVelocity: initialReorder.autoScrollMaxVelocity,
        ),
        initialConfig: initialReorder,
      );
      _syncGate = DeferredSyncGate<TKey>(
        reorderController: _reorderRuntime!.controller,
        isMounted: () {
          return mounted;
        },
        onSync: () {
          _sync(animate: true);
        },
      );
    }
    _syncController = _createSyncController();
    _sync(animate: false);
    _applyInitialExpansion(animate: false);
    // Hand the controller over only once the tree is in its settled
    // initial state: callers routinely query expansion or scroll straight
    // from this callback.
    widget.onControllerCreated?.call(_treeController);
    final runtime = _reorderRuntime;
    if (runtime != null) {
      _syncGate?.attach();
      runtime.initialConfig.onControllerCreated?.call(runtime.controller);
    }
    // Subscribe only AFTER the initial expansion pass. That pass is this
    // widget's own initialization, not an expansion change worth
    // reporting, and a consumer restoring persisted expansion would
    // otherwise immediately be told to overwrite it with the defaults.
    _treeController.addExpansionListener(_handleExpansionChanged);
  }

  /// Refuses everything when reorder is absent or disabled
  /// ([TreeReorderConfig.enabled] false), rather than defaulting to
  /// "allowed".
  ///
  /// RAW `widget.reorder`, deliberately, NOT the construction-time
  /// fallback that `build` uses.
  ///
  /// This is the POLICY side of a one-directional invariant: policy is a
  /// subset of presentation. Presentation must keep rendering from the
  /// last known config (see `build`); policy must refuse the moment the
  /// live config goes away. Routing this through the fallback instead
  /// turned a loud release crash into silent divergence, with drags
  /// committing and `onReorder` delivered to a closure the caller had
  /// already discarded.
  ///
  /// Fail-closed satisfies the invariant trivially and unfalsifiably: it
  /// is maximally restrictive, so no later change to presentation can
  /// break the pairing. And this is THE gate the whole commit path leans
  /// on, reached by `startDrag`, `updateDrag`, `endDrag` and `moveTo`
  /// alike, via `TreeReorderController._canCommit`.
  ///
  /// Load-bearing wiring, easy to undo by accident: the controller is
  /// given THIS tear-off, never `config.canReorder`. Every gate in the
  /// controller reads `canReorder != null && !canReorder!(...)`, so
  /// passing the user's nullable policy straight through would make all
  /// four of them vacuous.
  bool _handleCanReorder(TKey key) {
    final config = widget.reorder;
    // `!enabled` refuses on the same fail-closed footing as absence.
    // This ONE gate is what makes [TreeReorderConfig.enabled] cover
    // drag start, mid-drag enforcement, commits, `moveTo` and the
    // semantics actions alike: they all consult this tear-off.
    if (config == null || !config.enabled) {
      return false;
    }
    return config.canReorder?.call(key) ?? true;
  }

  /// Absent or disabled config refuses, on raw `widget.reorder`, for the
  /// reason [_handleCanReorder] gives.
  ///
  /// The two must agree: a null config that refused drags but permitted
  /// drops read as an accident rather than a policy, and left the pair
  /// only accidentally safe. An absent-but-present `canAcceptDrop` still
  /// defaults to "allowed", which is the actual default being expressed.
  bool _handleCanAcceptDrop({
    required TKey movingKey,
    TKey? newParent,
    int? index,
  }) {
    final config = widget.reorder;
    if (config == null || !config.enabled) {
      return false;
    }
    final policy = config.canAcceptDrop;
    if (policy == null) {
      return true;
    }
    return policy(movingKey: movingKey, newParent: newParent, index: index);
  }

  /// UNREACHABLE by construction, and asserted as a tripwire rather than
  /// as a diagnosis.
  ///
  /// Every route here runs through `TreeReorderController._fireOnReorder`,
  /// which only runs after `_canCommit`, whose first question is
  /// `canReorder` -- the always-non-null [_handleCanReorder] tear-off,
  /// which refuses a null config. So a null config commits nothing and
  /// reports nothing, on the drag path and through `moveTo` alike.
  ///
  /// The assert exists for the day someone relaxes [_handleCanReorder] to
  /// default-allow. That coupling is invisible from either site, and
  /// breaking it silently would mean the tree mutates while the app's
  /// model is never told. If this ever fires, fix the gate, not this.
  void _handleReorder(TKey key, TKey? newParent, int index) {
    final config = widget.reorder;
    assert(
      config != null,
      "TreeReorderController committed a move for $key while "
      "SyncedSliverTree.reorder was null, so onReorder cannot be "
      "delivered and the tree has silently diverged from its inputs.",
    );
    config?.onReorder(key, newParent, index);
  }

  Map<CustomSemanticsAction, VoidCallback> _handleSemanticsActions(
    TKey key,
    Map<CustomSemanticsAction, VoidCallback> builtIn,
  ) {
    final builder = widget.reorder?.semanticsActionsBuilder;
    return builder == null ? builtIn : builder(key, builtIn);
  }

  /// Stable forwarder for [SyncedSliverTree.onExpansionChanged]. Reading
  /// the callback through `widget` keeps a fresh inline closure on every
  /// rebuild from churning the controller's listener list.
  void _handleExpansionChanged(TKey key, bool isExpanded) {
    widget.onExpansionChanged?.call(key, isExpanded);
  }

  /// The initial-expansion policy for [key]: the per-node resolver when one
  /// is supplied (falling back to [SyncedSliverTree.initiallyExpanded] on a
  /// null result), otherwise the blanket flag.
  bool _resolveInitialExpansion(TKey key) {
    final resolver = widget.initialNodeExpansion;
    if (resolver == null) {
      return widget.initiallyExpanded;
    }
    final node = _treeController.getNodeData(key);
    if (node == null) {
      return widget.initiallyExpanded;
    }
    return resolver(key, node.data) ?? widget.initiallyExpanded;
  }

  /// Applies the initial-expansion policy to the whole tree. Called once,
  /// from [initState], after the first sync.
  void _applyInitialExpansion({required bool animate}) {
    if (widget.initialNodeExpansion == null) {
      // Blanket policy: the bulk path settles the whole tree in one pass.
      if (widget.initiallyExpanded) {
        _treeController.expandAll(animate: animate);
      }
      return;
    }
    // Only the key set is wanted here, and `snapshotChildPresence` carries
    // the same one without materializing a child list per node.
    final keys = _syncController.snapshotChildPresence().keys.toList(
      growable: false,
    );
    _treeController.runBatch(() {
      for (final key in keys) {
        // Nodes start collapsed, so only the expand side has work to do,
        // and expand() no-ops on childless nodes by itself.
        if (_resolveInitialExpansion(key)) {
          _treeController.expand(key: key, animate: animate);
        }
      }
    });
  }

  /// Applies the initial-expansion policy to nodes that appeared in the
  /// sync that just ran.
  ///
  /// [rememberedBeforeSync] is captured BEFORE that sync deliberately: the
  /// sync layer consumes remembered entries as it restores them, so a
  /// post-sync snapshot would no longer name the re-added nodes whose
  /// state was just restored. Skipping those keys here is what makes a
  /// restored expansion win over a conflicting policy.
  void _applyInitialExpansionToNewNodes({
    required Map<TKey, bool> previousPresence,
    required Iterable<TKey> currentKeys,
    required Set<TKey> rememberedBeforeSync,
    required bool animate,
  }) {
    _treeController.runBatch(() {
      for (final key in currentKeys) {
        // Membership is read off the presence map's key set directly; it
        // names exactly the nodes that were live before the sync, so
        // copying it into a Set first bought nothing.
        if (previousPresence.containsKey(key)) {
          continue;
        }
        if (rememberedBeforeSync.contains(key)) {
          continue;
        }
        if (!_resolveInitialExpansion(key)) {
          continue;
        }
        _treeController.expand(key: key, animate: animate);
      }
    });
  }

  TreeSyncController<TKey, TItem> _createSyncController() {
    return TreeSyncController<TKey, TItem>(
      treeController: _treeController,
      preserveExpansion: widget.preserveExpansion,
      maxExpansionMemorySize: widget.maxExpansionMemorySize,
    );
  }

  @override
  void didUpdateWidget(SyncedSliverTree<TKey, TItem> oldWidget) {
    super.didUpdateWidget(oldWidget);

    assert(
      (oldWidget.reorder == null) == (widget.reorder == null),
      "SyncedSliverTree.reorder cannot be added or removed after the "
      "widget is created: it changes the widget type at this slot, "
      "tearing down the sliver and its child caches, and would orphan a "
      "live drag. Keep the config and set enabled: false to disable "
      "reordering at runtime.",
    );
    if (oldWidget.animationStyle != widget.animationStyle) {
      _treeController.animationStyle = widget.animationStyle;
    }
    if (oldWidget.indentWidth != widget.indentWidth) {
      _treeController.indentWidth = widget.indentWidth;
    }
    // Drag tunings are live like every other config content: pushed onto
    // the controller's mutable fields, each captured per drag session at
    // startDrag, so a change applies from the next drag. Raw
    // `widget.reorder` like the policy forwarders: on a (release-mode)
    // presence flip the controller simply keeps its last tunings.
    final runtime = _reorderRuntime;
    final reorderConfig = widget.reorder;
    if (runtime != null && reorderConfig != null) {
      runtime.controller
        ..autoExpandDelay = reorderConfig.autoExpandDelay
        ..autoScrollEdgeZone = reorderConfig.autoScrollEdgeZone
        ..autoScrollMaxVelocity = reorderConfig.autoScrollMaxVelocity;
    }

    // ONE decision point. `needsSync` folds together the three reasons a
    // diff is owed, so "sync regardless of the identity gate" is a single
    // expression rather than a rule restated in three places.
    var needsSync = _syncGate?.isDeferred ?? false;

    if (widget.preserveExpansion != oldWidget.preserveExpansion ||
        widget.maxExpansionMemorySize != oldWidget.maxExpansionMemorySize) {
      // Recreated EAGERLY, even mid-drag. The sync controller touches no
      // tree structure: `initializeTracking` is a no-op and `dispose`
      // only clears two memory maps. Only its trailing diff is deferred,
      // which is what removes the second latch an earlier design needed
      // to remember this across a deferred run.
      _syncController.dispose();
      _syncController = _createSyncController();
      // A no-op today, and kept deliberately: it is the recreation
      // path's only hook, and dropping the call because the body is
      // currently empty would silently unhook this branch if it ever
      // gains one.
      _syncController.initializeTracking();
      needsSync = true;
    } else if (!_modeInputsIdentical(oldWidget)) {
      // Identity fast path: callers routinely rebuild an ancestor every
      // frame while passing the SAME collection instance, and re-running
      // the full diff is O(N) UI-thread work for zero change. Standard
      // Flutter convention (same as ListView.children): mutating a
      // collection in place requires a new instance to be observed.
      needsSync = true;
    }

    if (!needsSync) {
      return;
    }
    if (_syncGate?.isDragging ?? false) {
      // A diff underneath a live drag inserts and removes siblings around
      // the drop target, invalidates the pinned row, and fights the
      // make-room preview. Nothing is queued: `_sync` reads `widget`
      // fresh, so the gate's bit only means "the current input has not
      // been diffed yet", which is idempotent and always applies the
      // latest.
      _syncGate?.markDeferred();
      return;
    }
    _sync(animate: true);
    _syncGate?.markSynced();
  }

  /// Whether this widget's mode input is `identical` to [oldWidget]'s: per
  /// mode, the COLLECTION reference that feeds the diff.
  ///
  /// Extractor callbacks (`keyOf`, `childrenOf`, `parentOf`) are
  /// deliberately excluded. They are near-universally written as inline
  /// lambdas, which are a fresh closure instance on every build, so
  /// including them made this gate miss on every rebuild for the nodes,
  /// hierarchy and flat modes, which is exactly the O(N)-per-frame re-diff
  /// the gate exists to prevent. It instead requires the callbacks to be pure
  /// functions of their input, with a new collection instance signalling
  /// change (documented on every constructor).
  bool _modeInputsIdentical(SyncedSliverTree<TKey, TItem> oldWidget) {
    return switch (widget._mode) {
      _SyncedSliverTreeMode.tree => identical(oldWidget._tree, widget._tree),
      _SyncedSliverTreeMode.hierarchy => identical(
        oldWidget._hierarchyRoots,
        widget._hierarchyRoots,
      ),
      _SyncedSliverTreeMode.flat => identical(
        oldWidget._flatItems,
        widget._flatItems,
      ),
    };
  }

  void _sync({required bool animate}) {
    // ONE decision point for the post-sync expansion work. Both passes
    // below, and every input they need, hang off this: without a per-node
    // resolver and without the blanket flag there is nothing to expand, so
    // the pre-sync snapshot, the post-sync snapshot and the remembered-key
    // set would all be built and discarded. Each is a full walk of the live
    // tree, and this runs on every sync.
    final needsExpansionPasses =
        widget.initiallyExpanded || widget.initialNodeExpansion != null;
    final previousChildPresence = _hasSyncedOnce && needsExpansionPasses
        ? _syncController.snapshotChildPresence()
        : null;
    // Capture the set of keys with remembered expansion state BEFORE the
    // sync. syncRoots will clear entries as part of _restoreExpansion /
    // _pruneExpansionMemory, so by the time expandParentsThatGainedChildren
    // runs below, the memory no longer reflects which keys were filtered
    // out previously — and the heuristic would wrongly auto-expand a
    // re-added, user-collapsed section.
    final Set<TKey> rememberedBeforeSync = needsExpansionPasses
        ? _syncController.snapshotRememberedKeys()
        : const <Never>{};

    final normalized = _normalizeInput();
    _syncController.syncRoots(
      normalized.roots,
      childrenOf: normalized.childrenOf,
      animate: animate,
    );

    // Non-null only when `needsExpansionPasses` held, so reaching here
    // means at least pass 2 has work to do and the post-sync walk is owed.
    if (previousChildPresence != null) {
      final currentChildPresence = _syncController.snapshotChildPresence();
      // 1. The initial-expansion policy, for nodes that are new in THIS
      //    sync. Skipped entirely without a per-node resolver: the blanket
      //    flag's true case is already covered by the heuristic below, and
      //    its false case matches the collapsed state new nodes start in,
      //    so the walk would be pure cost for existing callers.
      if (widget.initialNodeExpansion != null) {
        _applyInitialExpansionToNewNodes(
          previousPresence: previousChildPresence,
          currentKeys: currentChildPresence.keys,
          rememberedBeforeSync: rememberedBeforeSync,
          animate: animate,
        );
      }
      // 2. Parents that gained their first children in this sync. Runs
      //    after pass 1; the two are idempotent where they overlap (both
      //    resolve through the same policy, and expand() no-ops on an
      //    already-expanded node), so the fixed order is for determinism.
      //    Unconditional: its gate IS `needsExpansionPasses`, resolved once
      //    above rather than restated here.
      expandParentsThatGainedChildren<TKey, TItem>(
        controller: _treeController,
        oldChildPresence: previousChildPresence,
        newChildPresence: currentChildPresence,
        rememberedBeforeSync: rememberedBeforeSync,
        animate: animate,
        shouldExpand: widget.initialNodeExpansion == null
            ? null
            : _resolveInitialExpansion,
      );
    }
    _hasSyncedOnce = true;
  }

  NormalizedTreeInput<TKey, TItem> _normalizeInput() {
    return switch (widget._mode) {
      _SyncedSliverTreeMode.tree => normalizeSyncedNodes(
        widget._tree as Iterable<SyncedTreeNode<TKey, TItem>>,
      ),
      _SyncedSliverTreeMode.hierarchy => normalizeHierarchy(
        roots: widget._hierarchyRoots as Iterable<TItem>,
        keyOf: widget._keyOf as TKey Function(TItem item),
        childrenOf: widget._childrenOf as Iterable<TItem> Function(TItem item),
      ),
      _SyncedSliverTreeMode.flat => normalizeFlat(
        items: widget._flatItems as Iterable<TItem>,
        keyOf: widget._keyOf as TKey Function(TItem item),
        parentOf: widget._parentOf as TKey? Function(TItem item),
      ),
    };
  }

  @override
  void dispose() {
    _treeController.removeExpansionListener(_handleExpansionChanged);
    // BEFORE the tree controller: tearing down a live session reaches
    // back into it (clearing the make-room preview) and into the render
    // port (unpinning the dragged row).
    _syncGate?.dispose();
    _reorderRuntime?.controller.dispose();
    _syncController.dispose();
    _treeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _reorderRuntime;
    if (runtime == null) {
      return SliverTree<TKey, TItem>(
        controller: _treeController,
        maxStickyDepth: widget.maxStickyDepth,
        addRepaintBoundaries: widget.addRepaintBoundaries,
        nodeBuilder: _buildRow,
      );
    }

    // The ONLY site that falls back to the construction-time config, and
    // the fallback is a correctness requirement rather than a concession.
    //
    // Presentation must stay BYTE-IDENTICAL across a presence flip. Every
    // input below feeds the row's widget shape, `buildDefaultDragHandles`
    // most of all: it decides whether a `TreeDelayedDragHandle` wraps the
    // row. Rendering a different shape fails `Widget.canUpdate`
    // and re-inflates every row subtree, disposing the app's `State`
    // underneath: half-typed text fields, scroll offsets, in-flight
    // AnimationControllers. Degrading here would trade a crash for data
    // loss.
    //
    // Policy is the opposite: the forwarders above read raw
    // `widget.reorder` and refuse. Policy is a SUBSET of presentation, so
    // a tree that still looks reorderable simply reorders nothing.
    //
    // No `!`: `runtime` is non-null in this branch, so its captured
    // config is a guaranteed fallback.
    final config = widget.reorder ?? runtime.initialConfig;
    return SliverReorderableTree<TKey, TItem>(
      controller: _treeController,
      reorderController: runtime.controller,
      maxStickyDepth: widget.maxStickyDepth,
      addRepaintBoundaries: widget.addRepaintBoundaries,
      // The pixel constant this widget actually renders with, read in the
      // opposite direction. Letting the two drift keys drop-depth
      // selection to a column that appears nowhere on screen.
      indentWidth: config.indentWidth ?? widget.indentWidth,
      showDragProxy: config.showDragProxy,
      dragProxyBuilder: config.dragProxyBuilder,
      hapticsOnDrag: config.hapticsOnDrag,
      semanticsActionsBuilder: _handleSemanticsActions,
      nodeBuilder: (context, key, depth) {
        final row = _buildRow(context, key, depth);
        if (!config.buildDefaultDragHandles) {
          // The caller owns the affordance. The row is still wrapped by
          // SliverReorderableTree, so the hide, the drop targeting and
          // the semantics actions are all unaffected.
          return row;
        }
        return TreeDelayedDragHandle(child: row);
      },
    );
  }

  Widget _buildRow(BuildContext context, TKey key, int depth) {
    final nodeData = _treeController.getNodeData(key);
    if (nodeData == null) {
      return const SizedBox.shrink();
    }
    return widget.itemBuilder(
      context,
      TreeItemView<TKey, TItem>(
        key: key,
        item: nodeData.data,
        depth: depth,
        parentKey: _treeController.getParent(key),
        controller: _treeController,
      ),
    );
  }
}
