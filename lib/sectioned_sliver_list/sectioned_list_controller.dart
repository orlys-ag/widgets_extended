/// Imperative controller for [SectionedSliverList].
///
/// Wraps a [TreeController] + [TreeSyncController] under the hood,
/// translating section/item-shaped operations into the underlying
/// 2-level tree representation. Users never see the internal
/// `SecKey` / `SecPayload` wrapper types.
library;

import 'package:flutter/widgets.dart';

import '../sliver_tree/animation_style.dart';
import '../sliver_tree/tree_controller.dart';
import '../sliver_tree/tree_sync_controller.dart';
import '../sliver_tree/types.dart';
import '_internal_keys.dart';

/// The imperative engine behind a [SectionedSliverList].
///
/// Owns the imperative API (`addItem`, `moveItem`, `setItems`,
/// `expandSection`, ...) and translates section/item-shaped operations
/// into the underlying 2-level tree.
///
/// In the declarative `SectionedSliverList`, the widget creates and
/// disposes one of these internally; a reference is surfaced to the
/// header/item builders via [SectionView.controller] /
/// [ItemView.controller]. There the `sections` / `itemsOf` props stay
/// authoritative — imperative mutations are reverted by the next
/// rebuild that re-runs the diff.
///
/// In `SectionedSliverList.controlled`, the caller constructs, owns and
/// disposes the controller, and it is the sole source of truth: no
/// diffing, nothing to revert against.
///
/// `SectionedListController` implements [Listenable]: [addListener] /
/// [removeListener] forward to the underlying [TreeController] and fire
/// on **structural** changes only (insert / remove / move / reorder /
/// expand / collapse). Payload-only mutations (`updateSection`,
/// `updateItem`) do NOT fire the structural channel — subscribe via
/// [addSectionPayloadListener] / [addItemPayloadListener] instead.
///
/// Inside [runBatch], structural notifications coalesce to a single
/// fire at batch exit, and payload notifications are deferred and
/// deduped by key.
///
/// **Unknown keys throw.** Every mutator and expansion method that takes
/// a section or item key ([setItems], [removeSection], [updateSection],
/// [moveSection], [addItem], [removeItem], [updateItem], [moveItem],
/// [reorderItems], [expandSection], [collapseSection], [toggleSection])
/// throws a [StateError] if the key is not present. Debug builds assert
/// first, so the failure surfaces at the call site during development;
/// release builds throw. Query with [hasSection] / [hasItem] when the
/// key's presence is not already guaranteed.
class SectionedListController<K extends Object, Section, Item>
    implements Listenable {
  SectionedListController({
    required TickerProvider vsync,
    required this.sectionKeyOf,
    required this.itemKeyOf,
    TreeAnimationStyle animationStyle = const TreeAnimationStyle(),
    double itemIndent = 0.0,
    bool preserveExpansion = true,
  }) : _tree = TreeController<SecKey<K>, SecPayload<Section, Item>>(
         vsync: vsync,
         animationStyle: animationStyle,
         indentWidth: itemIndent,
       ),
       _preserveExpansion = preserveExpansion {
    // The tree layer merged its two expansion-memory knobs into one int;
    // this module keeps the friendlier bool (it never exposed the
    // capacity) and maps it onto the shared default.
    _sync = TreeSyncController<SecKey<K>, SecPayload<Section, Item>>(
      treeController: _tree,
      expansionMemory: preserveExpansion
          ? TreeSyncController.defaultExpansionMemory
          : 0,
    );
    // Single underlying TreeController node-data listener that fans out
    // into the two domain-specific listener lists. Attached unconditionally;
    // dispatch is cheap (one type test, one list iteration that is empty
    // when nothing subscribes).
    _tree.addNodeDataListener(_dispatchPayloadNotification);
  }

  /// Extracts the section's stable key from its payload. Captured at
  /// construction so all controller-side methods can convert
  /// user-supplied `Section` values into keys without callers having to
  /// pass the key explicitly.
  final K Function(Section section) sectionKeyOf;

  /// Extracts the item's stable key from its payload. Same role as
  /// [sectionKeyOf].
  final K Function(Item item) itemKeyOf;

  final TreeController<SecKey<K>, SecPayload<Section, Item>> _tree;
  late TreeSyncController<SecKey<K>, SecPayload<Section, Item>> _sync;
  bool _preserveExpansion;

  final List<void Function(K sectionKey)> _sectionPayloadListeners = [];
  final List<void Function(K itemKey)> _itemPayloadListeners = [];

  bool _disposed = false;

  // ──────────────────────────────────────────────────────────────────
  // Internal hooks (used by the SectionedSliverList State; not for end
  // users)
  // ──────────────────────────────────────────────────────────────────

  /// Underlying tree controller. Exposed for the widget's render layer
  /// (it must construct a `SliverTree` against this). Not part of the
  /// supported public API for end users — calling structural methods
  /// directly on the underlying tree bypasses the section/item type
  /// invariants this controller enforces.
  TreeController<SecKey<K>, SecPayload<Section, Item>> get treeController {
    return _tree;
  }

  // ──────────────────────────────────────────────────────────────────
  // Configuration setters
  // ──────────────────────────────────────────────────────────────────

  /// Animation timing/easing for every family. Forwards to
  /// [TreeController.animationStyle] — see it for the runtime-mutation
  /// semantics.
  set animationStyle(TreeAnimationStyle value) {
    _checkNotDisposed();
    _tree.animationStyle = value;
  }

  TreeAnimationStyle get animationStyle {
    _checkNotDisposed();
    return _tree.animationStyle;
  }

  /// Visual indent applied to items under section headers, in logical
  /// pixels. Forwards to [TreeController.indentWidth].
  set itemIndent(double value) {
    _checkNotDisposed();
    _tree.indentWidth = value;
  }

  double get itemIndent {
    _checkNotDisposed();
    return _tree.indentWidth;
  }

  bool get preserveExpansion {
    return _preserveExpansion;
  }

  set preserveExpansion(bool value) {
    if (value == _preserveExpansion) {
      return;
    }
    _preserveExpansion = value;
    _sync.dispose();
    _sync = TreeSyncController<SecKey<K>, SecPayload<Section, Item>>(
      treeController: _tree,
      expansionMemory: value ? TreeSyncController.defaultExpansionMemory : 0,
    );
    _sync.initializeTracking();
  }

  /// Snapshots used by the widget's initial-expansion logic (mirrors
  /// the existing public hooks on `TreeSyncController`).
  Map<K, List<K>> debugSnapshotCurrentChildren() {
    final raw = _sync.snapshotCurrentChildren();
    final out = <K, List<K>>{};
    for (final entry in raw.entries) {
      final parent = entry.key;
      if (parent is! SectionKey<K>) {
        continue;
      }
      out[parent.value] = <K>[
        for (final c in entry.value)
          if (c is ItemKey<K>) c.value,
      ];
    }
    return out;
  }

  /// Section keys whose expansion state is currently REMEMBERED, meaning
  /// the section is not in the tree right now but its expanded/collapsed
  /// state is being held for a re-add. Empty when [preserveExpansion] is
  /// off.
  ///
  /// A caller that applies its own initial-expansion policy must skip
  /// these keys: a remembered section is not a new one, and forcing the
  /// policy onto it discards the state the user set before it was
  /// filtered out. That is exactly what the declarative widget does with
  /// this, mirroring `SyncedSliverTree`'s `rememberedBeforeSync` pass.
  ///
  /// Snapshot the set BEFORE the sync that may re-add the section: the
  /// sync spends the memory it restores.
  Set<K> rememberedSectionKeys() {
    _checkNotDisposed();
    final out = <K>{};
    for (final k in _sync.snapshotRememberedKeys()) {
      if (k is SectionKey<K>) {
        out.add(k.value);
      }
    }
    return out;
  }

  // ──────────────────────────────────────────────────────────────────
  // Public API — bulk
  // ──────────────────────────────────────────────────────────────────

  /// Replaces all sections. Diffs against current state and animates
  /// inserts, removes, and reparenting.
  ///
  /// [itemsOf] is invoked once per [sections] entry to materialize the
  /// section's items. Callers may pass any [Iterable] (e.g., a
  /// `where`/`map` chain); this method consumes it eagerly.
  void setSections(
    Iterable<Section> sections, {
    required Iterable<Item> Function(Section section) itemsOf,
    bool animate = true,
  }) {
    _checkNotDisposed();
    // Re-initialize the sync controller's tracking so the diff is
    // computed against the actual current tree state. Necessary because
    // direct mutations via this controller (addItem, removeItem, ...)
    // bypass the sync controller's bookkeeping; without this, a
    // setSections after such mutations would diff against a stale
    // baseline and fail to remove drifted nodes.
    _sync.initializeTracking();

    final list = sections.toList(growable: false);
    final desired = <TreeNode<SecKey<K>, SecPayload<Section, Item>>>[
      for (final s in list)
        TreeNode(
          key: SectionKey<K>(sectionKeyOf(s)),
          data: SectionPayload<Section, Item>(s),
        ),
    ];
    final byKey = <K, Section>{for (final s in list) sectionKeyOf(s): s};
    _sync.syncRoots(
      desired,
      childrenOf: (k) {
        if (k is! SectionKey<K>) {
          return const [];
        }
        final section = byKey[k.value];
        if (section == null) {
          return const [];
        }
        return <TreeNode<SecKey<K>, SecPayload<Section, Item>>>[
          for (final i in itemsOf(section))
            TreeNode(
              key: ItemKey<K>(itemKeyOf(i)),
              data: ItemPayload<Section, Item>(i),
            ),
        ];
      },
      animate: animate,
    );
  }

  /// Replaces all items under [sectionKey]. Diffs against current
  /// children and animates inserts/removes.
  void setItems(K sectionKey, Iterable<Item> items, {bool animate = true}) {
    _checkNotDisposed();
    _requireSection(sectionKey, "setItems");
    _requireItemsFree(
      [for (final i in items) itemKeyOf(i)],
      "setItems",
      exceptInSection: sectionKey,
    );
    // Re-initialize tracking so the diff is computed against the actual
    // current state — see [setSections] for the rationale.
    _sync.initializeTracking();
    final desired = <TreeNode<SecKey<K>, SecPayload<Section, Item>>>[
      for (final i in items)
        TreeNode(
          key: ItemKey<K>(itemKeyOf(i)),
          data: ItemPayload<Section, Item>(i),
        ),
    ];
    _sync.syncChildren(SectionKey<K>(sectionKey), desired, animate: animate);
  }

  // ──────────────────────────────────────────────────────────────────
  // Public API — section-scoped
  // ──────────────────────────────────────────────────────────────────

  /// Inserts [section] at [index] (or at the end when null). If [items]
  /// is non-empty they become the section's children — this initial
  /// child population is structural and does not animate per item; the
  /// section's own appearance respects [animate].
  void addSection(
    Section section, {
    int? index,
    Iterable<Item>? items,
    bool animate = true,
  }) {
    _checkNotDisposed();
    final sectionKey = sectionKeyOf(section);
    // A section that is mid-EXIT is excluded: addSection on it is the
    // documented re-include path, which cancels the deletion through
    // insertRoot. `hasSection` reads the node data, which an exiting
    // section still has.
    if (hasSection(sectionKey) &&
        !_tree.isPendingDeletion(SectionKey<K>(sectionKey))) {
      throw ArgumentError(
        "SectionedListController.addSection: section $sectionKey already "
        "exists. Use setItems() or updateSection() instead.",
      );
    }
    if (items != null) {
      _requireItemsFree([for (final i in items) itemKeyOf(i)], "addSection");
    }
    _tree.runBatch(() {
      _tree.insertRoot(
        TreeNode(
          key: SectionKey<K>(sectionKey),
          data: SectionPayload<Section, Item>(section),
        ),
        index: index,
        animate: animate,
      );
      if (items != null) {
        final children = <TreeNode<SecKey<K>, SecPayload<Section, Item>>>[
          for (final i in items)
            TreeNode(
              key: ItemKey<K>(itemKeyOf(i)),
              data: ItemPayload<Section, Item>(i),
            ),
        ];
        if (children.isNotEmpty) {
          _tree.setChildren(SectionKey<K>(sectionKey), children);
        }
      }
    });
  }

  void removeSection(K sectionKey, {bool animate = true}) {
    _checkNotDisposed();
    _requireSection(sectionKey, "removeSection");
    _tree.remove(key: SectionKey<K>(sectionKey), animate: animate);
  }

  /// Updates [sectionKey]'s payload to [section] without touching the
  /// section's items. Asserts that [sectionKey] already exists.
  ///
  /// The key is taken explicitly rather than inferred from
  /// `sectionKeyOf(section)` so that a copy-with that nudges the id
  /// field surfaces as a missing-key assertion instead of silently
  /// corrupting the tree.
  void updateSection(K sectionKey, Section section) {
    _checkNotDisposed();
    _requireSection(sectionKey, "updateSection");
    _tree.updateNode(
      TreeNode(
        key: SectionKey<K>(sectionKey),
        data: SectionPayload<Section, Item>(section),
      ),
    );
  }

  void reorderSections(List<K> orderedKeys) {
    _checkNotDisposed();
    _tree.reorderRoots(<SecKey<K>>[
      for (final k in orderedKeys) SectionKey<K>(k),
    ]);
  }

  void moveSection(K sectionKey, int toIndex) {
    _checkNotDisposed();
    _requireSection(sectionKey, "moveSection");
    if (_tree.isPendingDeletion(SectionKey<K>(sectionKey))) {
      _throwMissing("moveSection", "section $sectionKey is being removed");
    }
    // Use the LIVE list — `reorderSections` → `_tree.reorderRoots`
    // validates against the live root set (excludes pending-deletion).
    // The previous full-list form would build a proposed order
    // including pending-deletion siblings and trip the validation when
    // a sibling section was mid-exit-animation.
    final order = sectionKeys()..remove(sectionKey);
    final clamped = toIndex.clamp(0, order.length);
    order.insert(clamped, sectionKey);
    reorderSections(order);
  }

  // ──────────────────────────────────────────────────────────────────
  // Public API — item-scoped
  // ──────────────────────────────────────────────────────────────────

  /// Inserts [item] under [toSection] at [index] (or at the end).
  void addItem(
    Item item, {
    required K toSection,
    int? index,
    bool animate = true,
  }) {
    _checkNotDisposed();
    _requireSection(toSection, "addItem");
    // Scoped to OTHER sections: re-adding into `toSection` is either the
    // cancel-deletion path for a mid-exit item or an in-section upsert,
    // both of which `insert` handles.
    _requireItemsFree(
      [itemKeyOf(item)],
      "addItem",
      exceptInSection: toSection,
    );
    _tree.insert(
      parentKey: SectionKey<K>(toSection),
      node: TreeNode(
        key: ItemKey<K>(itemKeyOf(item)),
        data: ItemPayload<Section, Item>(item),
      ),
      index: index,
      animate: animate,
    );
  }

  void removeItem(K itemKey, {bool animate = true}) {
    _checkNotDisposed();
    _requireItem(itemKey, "removeItem");
    _tree.remove(key: ItemKey<K>(itemKey), animate: animate);
  }

  /// Updates [itemKey]'s payload to [item]. Asserts that [itemKey]
  /// already exists. See [updateSection] for why the key is explicit.
  void updateItem(K itemKey, Item item) {
    _checkNotDisposed();
    _requireItem(itemKey, "updateItem");
    _tree.updateNode(
      TreeNode(
        key: ItemKey<K>(itemKey),
        data: ItemPayload<Section, Item>(item),
      ),
    );
  }

  /// Repositions [itemKey], either across sections or within its own.
  ///
  ///   • [toSection] non-null → reparents the item under that section.
  ///     With [index] it lands at that position; without, it is
  ///     appended.
  ///   • [toSection] null, [index] non-null → reorders the item within
  ///     its current section to [index].
  ///   • both null → no-op.
  ///
  /// Both forms animate when [animate] is true (the default), and both
  /// animate the same way: a paint-only FLIP slide from each affected
  /// row's old painted position to its new one. Nothing enters or leaves
  /// on either path, so neither produces per-row enter/exit animations.
  ///
  ///   - A cross-section reparent slides the moved row, timed by
  ///     [slideDuration] / [slideCurve].
  ///   - An in-section reorder slides every row whose position changed,
  ///     and only while the section is expanded: a reorder inside a
  ///     collapsed section has nothing on screen to slide. It does not
  ///     read [slideDuration] / [slideCurve], which name the moved row's
  ///     own glide and have no single subject here.
  ///
  /// Timing comes from the controller's expand/collapse spec
  /// (`animationStyle.expandCollapse`) on both paths, so a move stays in
  /// sync with the inserts, removes, expands and collapses it may compose
  /// with inside one [runBatch]. Note the asymmetry the in-section path
  /// inherits from [reorderItems]: zeroing `reorderSlide` disables its
  /// slide even though the duration comes from `expandCollapse`.
  void moveItem(
    K itemKey, {
    K? toSection,
    int? index,
    bool animate = true,
    Duration? slideDuration,
    Curve? slideCurve,
  }) {
    _checkNotDisposed();
    _requireItem(itemKey, "moveItem");
    // Hoisted above the branch: the in-section path always refused a
    // vanishing item, while the cross-section path fell through to
    // moveNode, which CANCELS the deletion and resurrects it.
    if (_tree.isPendingDeletion(ItemKey<K>(itemKey))) {
      _throwMissing("moveItem", "item $itemKey is being removed");
    }
    if (toSection != null) {
      _requireSection(toSection, "moveItem(toSection)");
      // Documented as "appended" when [index] is null. moveNode treats a
      // same-parent move with no index as a no-op, so name the last live
      // slot explicitly; its own live-space guard keeps an already-last
      // item a no-op.
      final int? effectiveIndex =
          index ??
          (sectionOf(itemKey) == toSection
              ? _tree.liveChildCount(SectionKey<K>(toSection)) - 1
              : null);
      _tree.moveNode(
        ItemKey<K>(itemKey),
        SectionKey<K>(toSection),
        index: effectiveIndex,
        animate: animate,
        slideDuration:
            slideDuration ?? _tree.animationStyle.expandCollapse.duration,
        slideCurve: slideCurve ?? _tree.animationStyle.expandCollapse.curve,
      );
      return;
    }
    if (index == null) {
      // Neither a reparent target nor a reorder index — nothing to do.
      return;
    }
    final parentKey = sectionOf(itemKey);
    if (parentKey == null) {
      _throwMissing("moveItem", "item $itemKey has no parent section");
    }
    // Use the LIVE list — `reorderItems` → `_tree.reorderChildren`
    // validates against the live child set (excludes pending-deletion).
    final siblings = itemKeysOf(parentKey)..remove(itemKey);
    final clamped = index.clamp(0, siblings.length);
    siblings.insert(clamped, itemKey);
    // Forward [animate]. Dropping it here made `animate: false` slide
    // anyway on this path only, which is what let the old doc claim this
    // form "never animates regardless of animate" and stay unchallenged.
    reorderItems(parentKey, siblings, animate: animate);
  }

  /// Reorders [sectionKey]'s items to match [orderedKeys].
  ///
  /// When [animate] is true (the default) and the section is expanded,
  /// rows whose position changed get a paint-only FLIP slide from their
  /// old painted position to their new one. Nothing enters or leaves, so
  /// there are no per-row enter/exit animations either way.
  ///
  /// The slide is timed with `animationStyle.expandCollapse` rather than
  /// `reorderSlide`, so a sectioned reorder stays in lockstep with the
  /// inserts, removes, expands and collapses it may compose with inside
  /// one [runBatch]. Note the asymmetry that follows from riding the
  /// tree's reorder machinery with another family's timing: zeroing
  /// `reorderSlide` disables this slide even though its duration comes
  /// from `expandCollapse`.
  void reorderItems(
    K sectionKey,
    List<K> orderedKeys, {
    bool animate = true,
  }) {
    _checkNotDisposed();
    _requireSection(sectionKey, "reorderItems");
    _tree.reorderChildren(
      SectionKey<K>(sectionKey),
      <SecKey<K>>[for (final k in orderedKeys) ItemKey<K>(k)],
      animate: animate,
      slideDuration: _tree.animationStyle.expandCollapse.duration,
      slideCurve: _tree.animationStyle.expandCollapse.curve,
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Public API — expansion
  // ──────────────────────────────────────────────────────────────────

  void expandSection(K sectionKey, {bool animate = true}) {
    _checkNotDisposed();
    _requireSection(sectionKey, "expandSection");
    _tree.expand(key: SectionKey<K>(sectionKey), animate: animate);
  }

  void collapseSection(K sectionKey, {bool animate = true}) {
    _checkNotDisposed();
    _requireSection(sectionKey, "collapseSection");
    _tree.collapse(key: SectionKey<K>(sectionKey), animate: animate);
  }

  void toggleSection(K sectionKey, {bool animate = true}) {
    _checkNotDisposed();
    _requireSection(sectionKey, "toggleSection");
    _tree.toggle(key: SectionKey<K>(sectionKey), animate: animate);
  }

  void expandAll({bool animate = true}) {
    _checkNotDisposed();
    _tree.expandAll(animate: animate);
  }

  void collapseAll({bool animate = true}) {
    _checkNotDisposed();
    _tree.collapseAll(animate: animate);
  }

  // ──────────────────────────────────────────────────────────────────
  // Public API — queries
  //
  // Queries return LIVE entries (excluding nodes mid-exit-animation) by
  // default. Pass `includeExiting: true` to also include
  // pending-deletion nodes — an escape hatch for callers that need to
  // introspect mid-animation state.
  // ──────────────────────────────────────────────────────────────────

  bool hasSection(K sectionKey) {
    _checkNotDisposed();
    return _tree.getNodeData(SectionKey<K>(sectionKey)) != null;
  }

  bool hasItem(K itemKey) {
    _checkNotDisposed();
    return _tree.getNodeData(ItemKey<K>(itemKey)) != null;
  }

  Section? getSection(K sectionKey) {
    _checkNotDisposed();
    final node = _tree.getNodeData(SectionKey<K>(sectionKey));
    if (node == null) {
      return null;
    }
    final data = node.data;
    assert(
      data is SectionPayload<Section, Item>,
      "Node at SectionKey($sectionKey) is not a SectionPayload — tree invariant violated",
    );
    return (data as SectionPayload<Section, Item>).value;
  }

  Item? getItem(K itemKey) {
    _checkNotDisposed();
    final node = _tree.getNodeData(ItemKey<K>(itemKey));
    if (node == null) {
      return null;
    }
    final data = node.data;
    assert(
      data is ItemPayload<Section, Item>,
      "Node at ItemKey($itemKey) is not an ItemPayload — tree invariant violated",
    );
    return (data as ItemPayload<Section, Item>).value;
  }

  K? sectionOf(K itemKey) {
    _checkNotDisposed();
    final parent = _tree.getParent(ItemKey<K>(itemKey));
    if (parent == null) {
      return null;
    }
    assert(
      parent is SectionKey<K>,
      "Item $itemKey has a non-section parent — tree invariant violated",
    );
    return (parent as SectionKey<K>).value;
  }

  /// Section payloads in render order. Excludes sections currently
  /// mid-exit-animation unless [includeExiting] is true. The live form
  /// is the input shape `reorderSections` implicitly expects (via the
  /// keys returned by [sectionKeys]).
  List<Section> sections({bool includeExiting = false}) {
    _checkNotDisposed();
    final keys = includeExiting ? _tree.rootKeys : _tree.liveRootKeys;
    final out = <Section>[];
    for (final k in keys) {
      if (!_assertIsSection(k)) {
        continue;
      }
      final node = _tree.getNodeData(k);
      if (node == null) {
        continue;
      }
      final data = node.data;
      if (data is SectionPayload<Section, Item>) {
        out.add(data.value);
      }
    }
    return out;
  }

  /// Section keys in render order. Excludes pending-deletion sections
  /// unless [includeExiting] is true.
  List<K> sectionKeys({bool includeExiting = false}) {
    _checkNotDisposed();
    final keys = includeExiting ? _tree.rootKeys : _tree.liveRootKeys;
    return <K>[
      for (final k in keys)
        if (_assertIsSection(k)) (k as SectionKey<K>).value,
    ];
  }

  /// Item payloads under [sectionKey] in render order. Excludes
  /// pending-deletion items unless [includeExiting] is true. Returns
  /// `[]` for unknown sections.
  List<Item> itemsOf(K sectionKey, {bool includeExiting = false}) {
    _checkNotDisposed();
    final children = includeExiting
        ? _tree.getChildren(SectionKey<K>(sectionKey))
        : _tree.getLiveChildren(SectionKey<K>(sectionKey));
    if (children.isEmpty) {
      return const [];
    }
    final out = <Item>[];
    for (final k in children) {
      if (!_assertIsItem(k)) {
        continue;
      }
      final node = _tree.getNodeData(k);
      if (node == null) {
        continue;
      }
      final data = node.data;
      if (data is ItemPayload<Section, Item>) {
        out.add(data.value);
      }
    }
    return out;
  }

  /// Item keys under [sectionKey] in render order. Excludes
  /// pending-deletion items unless [includeExiting] is true.
  List<K> itemKeysOf(K sectionKey, {bool includeExiting = false}) {
    _checkNotDisposed();
    final children = includeExiting
        ? _tree.getChildren(SectionKey<K>(sectionKey))
        : _tree.getLiveChildren(SectionKey<K>(sectionKey));
    if (children.isEmpty) {
      return const [];
    }
    return <K>[
      for (final k in children)
        if (_assertIsItem(k)) (k as ItemKey<K>).value,
    ];
  }

  bool isExpanded(K sectionKey) {
    _checkNotDisposed();
    return _tree.isExpanded(SectionKey<K>(sectionKey));
  }

  /// Number of items currently belonging to [sectionKey], regardless
  /// of expansion state. Returns `0` for unknown sections. Includes
  /// pending-deletion children — this is the count rendered by the
  /// header, since exit animations are still visible.
  int itemCount(K sectionKey) {
    _checkNotDisposed();
    return _tree.getChildCount(SectionKey<K>(sectionKey));
  }

  /// Position of [itemKey] among its section's children in
  /// **live-list space** (skipping pending-deletion siblings). Returns
  /// `-1` when [itemKey] is not present, is itself pending-deletion, or
  /// is not an item.
  int indexOfItem(K itemKey) {
    _checkNotDisposed();
    return _tree.getIndexInParent(ItemKey<K>(itemKey));
  }

  // ──────────────────────────────────────────────────────────────────
  // Public API — notifications (Listenable)
  // ──────────────────────────────────────────────────────────────────

  /// Subscribes to **structural** changes. Fires once per mutation
  /// (insert / remove / move / reorder / expand / collapse), or once
  /// per outermost [runBatch] regardless of how many structural
  /// mutations the body contained.
  ///
  /// Payload-only mutations ([updateSection] / [updateItem]) do NOT
  /// fire this channel — subscribe to [addSectionPayloadListener] /
  /// [addItemPayloadListener] instead.
  @override
  void addListener(VoidCallback listener) {
    _checkNotDisposed();
    _tree.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_disposed) {
      return;
    }
    _tree.removeListener(listener);
  }

  // ──────────────────────────────────────────────────────────────────
  // Public API — typed payload listeners
  // ──────────────────────────────────────────────────────────────────

  /// Subscribes to section-payload changes. Fires after every
  /// successful [updateSection] call with the affected key. Inside
  /// [runBatch], multiple `updateSection(k, ...)` calls for the same
  /// `k` produce a single callback at batch exit.
  ///
  /// Domain-filtered, not key-filtered: the listener fires for every
  /// section payload change regardless of which section. Filter on the
  /// [sectionKey] argument inside your callback.
  void addSectionPayloadListener(void Function(K sectionKey) listener) {
    _checkNotDisposed();
    _sectionPayloadListeners.add(listener);
  }

  void removeSectionPayloadListener(void Function(K sectionKey) listener) {
    if (_disposed) {
      return;
    }
    _sectionPayloadListeners.remove(listener);
  }

  /// Subscribes to item-payload changes. Fires after every successful
  /// [updateItem] call with the affected key. Inside [runBatch],
  /// multiple `updateItem(k, ...)` calls for the same `k` produce a
  /// single callback at batch exit.
  ///
  /// Domain-filtered, not key-filtered: see [addSectionPayloadListener].
  void addItemPayloadListener(void Function(K itemKey) listener) {
    _checkNotDisposed();
    _itemPayloadListeners.add(listener);
  }

  void removeItemPayloadListener(void Function(K itemKey) listener) {
    if (_disposed) {
      return;
    }
    _itemPayloadListeners.remove(listener);
  }

  void _dispatchPayloadNotification(SecKey<K> wrapped) {
    if (_disposed) {
      return;
    }
    if (wrapped is SectionKey<K>) {
      if (_sectionPayloadListeners.isEmpty) {
        return;
      }
      // Iterate over a snapshot so a listener that removes itself does
      // not corrupt the iteration.
      final snapshot = List<void Function(K)>.of(_sectionPayloadListeners);
      for (final l in snapshot) {
        l(wrapped.value);
      }
    } else if (wrapped is ItemKey<K>) {
      if (_itemPayloadListeners.isEmpty) {
        return;
      }
      final snapshot = List<void Function(K)>.of(_itemPayloadListeners);
      for (final l in snapshot) {
        l(wrapped.value);
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Public API — batching
  // ──────────────────────────────────────────────────────────────────

  /// Coalesces structural notifications across the mutations performed
  /// inside [body] into a single post-batch refresh. Payload
  /// notifications are also coalesced and deduped by key. Delegates to
  /// the underlying [TreeController.runBatch].
  T runBatch<T>(T Function() body) {
    _checkNotDisposed();
    return _tree.runBatch<T>(body);
  }

  // ──────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _tree.removeNodeDataListener(_dispatchPayloadNotification);
    _sectionPayloadListeners.clear();
    _itemPayloadListeners.clear();
    _sync.dispose();
    _tree.dispose();
  }

  // ──────────────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────────────

  void _checkNotDisposed() {
    assert(!_disposed, "SectionedListController used after dispose()");
  }

  /// Rejects item keys that already live in a section other than
  /// [exceptInSection], and duplicates within [keys].
  ///
  /// Runs BEFORE any tree mutation so a caller's batch cannot fail
  /// halfway. The underlying tree would reject a cross-parent duplicate
  /// on its own, but it does so in terms of the internal `SectionKey` /
  /// `ItemKey` wrappers and only once the mutation is already under way.
  ///
  /// [exceptInSection] keeps the two legitimate same-section cases
  /// working: re-adding an item that is mid-exit (which cancels its
  /// deletion) and re-sending a live item (an in-section upsert).
  void _requireItemsFree(
    Iterable<K> keys,
    String method, {
    K? exceptInSection,
  }) {
    final seen = <K>{};
    for (final key in keys) {
      if (!seen.add(key)) {
        throw ArgumentError(
          "SectionedListController.$method: duplicate item key $key",
        );
      }
      final owner = sectionOf(key);
      if (owner != null && owner != exceptInSection) {
        throw ArgumentError(
          "SectionedListController.$method: item $key already exists in "
          "section $owner. Use moveItem() or removeItem() first.",
        );
      }
    }
  }

  void _requireSection(K sectionKey, String method) {
    if (_tree.getNodeData(SectionKey<K>(sectionKey)) == null) {
      _throwMissing(method, "no section with key $sectionKey");
    }
  }

  void _requireItem(K itemKey, String method) {
    if (_tree.getNodeData(ItemKey<K>(itemKey)) == null) {
      _throwMissing(method, "no item with key $itemKey");
    }
  }

  Never _throwMissing(String method, String detail) {
    final message = "SectionedListController.$method: $detail";
    assert(false, message);
    throw StateError(message);
  }

  bool _assertIsSection(SecKey<K> k) {
    assert(
      k is SectionKey<K>,
      "Expected a SectionKey at root level but found $k — "
      "tree invariant violated",
    );
    return k is SectionKey<K>;
  }

  bool _assertIsItem(SecKey<K> k) {
    assert(
      k is ItemKey<K>,
      "Expected an ItemKey under a section but found $k — "
      "tree invariant violated",
    );
    return k is ItemKey<K>;
  }
}
