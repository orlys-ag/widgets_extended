/// Imperative controller for [SectionedSliverList].
///
/// Wraps a [TreeController] + [TreeSyncController] under the hood,
/// translating section/item-shaped operations into the underlying
/// 2-level tree representation. Users never see the internal
/// `SecKey` / `SecPayload` wrapper types.
library;

import 'package:flutter/widgets.dart';

import '../sliver_tree/tree_controller.dart';
import '../sliver_tree/tree_sync_controller.dart';
import '../sliver_tree/types.dart';
import '_internal_keys.dart';
import 'section_input.dart';

/// Controller for a [SectionedSliverList].
///
/// Owns the imperative API (`addItem`, `moveItem`, `setItems`,
/// `expandSection`, ...). When supplied to a `SectionedSliverList` via
/// the optional `controller` parameter, the widget binds to it and
/// drives it from its declarative `sections` / `grouped` input. Users
/// can also call mutating methods between widget rebuilds to drift
/// state outside the declarative source — but the next widget rebuild
/// with a different `sections` value re-syncs to that input (the
/// "source of truth on rebuild" rule).
///
/// Lifetime: must be disposed by the owner. If you do not pass an
/// external controller to the widget, the widget creates one
/// internally and disposes it for you. If you do pass one, you keep
/// it across rebuilds and call [dispose] yourself when finished.
///
/// A controller is designed to drive exactly one widget at a time.
/// Mounting two widgets against the same controller asserts in debug.
class SectionedListController<SKey, IKey, Section, Item> {
  SectionedListController({
    required TickerProvider vsync,
    Duration animationDuration = const Duration(milliseconds: 300),
    Curve animationCurve = Curves.easeInOut,
    bool preserveExpansion = true,
  }) : _tree = TreeController<SecKey<SKey, IKey>, SecPayload<Section, Item>>(
         vsync: vsync,
         animationDuration: animationDuration,
         animationCurve: animationCurve,
       ),
       _preserveExpansion = preserveExpansion {
    _sync = TreeSyncController<SecKey<SKey, IKey>, SecPayload<Section, Item>>(
      treeController: _tree,
      preserveExpansion: preserveExpansion,
    );
  }

  final TreeController<SecKey<SKey, IKey>, SecPayload<Section, Item>> _tree;
  late TreeSyncController<SecKey<SKey, IKey>, SecPayload<Section, Item>> _sync;
  bool _preserveExpansion;

  int _bindingCount = 0;
  bool _disposed = false;

  // ──────────────────────────────────────────────────────────────────
  // Internal hooks (used by SectionedSliverListState; not for end users)
  // ──────────────────────────────────────────────────────────────────

  /// Underlying tree controller. Exposed for the widget's render layer
  /// (it must construct a `SliverTree` against this). Not part of the
  /// supported public API for end users — calling structural methods
  /// directly on the underlying tree bypasses the section/item type
  /// invariants this controller enforces.
  TreeController<SecKey<SKey, IKey>, SecPayload<Section, Item>>
  get treeController {
    return _tree;
  }

  /// Marks this controller as bound to a widget. Asserts that no other
  /// widget is currently bound. Called by `SectionedSliverListState`
  /// during `initState` and after a controller swap.
  ///
  /// The assert runs *before* the increment so a failed bind leaves
  /// internal state unchanged. In release builds the assert is stripped
  /// and the increment proceeds regardless — release-mode misuse will
  /// merely over-count, not corrupt the underlying tree.
  void debugBindWidget() {
    assert(
      _bindingCount < 1,
      "SectionedListController is already bound to another "
      "SectionedSliverList. A controller may drive only one widget at "
      "a time.",
    );
    _bindingCount++;
  }

  /// Releases the binding established by [debugBindWidget]. Called by
  /// `SectionedSliverListState` during `dispose` and before a controller
  /// swap.
  void debugUnbindWidget() {
    assert(
      _bindingCount > 0,
      "SectionedListController binding count would go negative. "
      "debugUnbindWidget called more times than debugBindWidget.",
    );
    _bindingCount--;
  }

  /// Animation params and `preserveExpansion` may be mutated by an
  /// internally-owned widget propagating its `widget.animationDuration`
  /// etc. across rebuilds. External controllers are authoritative for
  /// these and the widget refuses to overwrite them.
  set animationDuration(Duration value) {
    _tree.animationDuration = value;
  }

  set animationCurve(Curve value) {
    _tree.animationCurve = value;
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
    _sync = TreeSyncController<SecKey<SKey, IKey>, SecPayload<Section, Item>>(
      treeController: _tree,
      preserveExpansion: value,
    );
    _sync.initializeTracking();
  }

  /// Snapshots used by the widget's initial-expansion logic (mirrors
  /// the existing public hooks on `TreeSyncController`).
  Map<SKey, List<IKey>> debugSnapshotCurrentChildren() {
    final raw = _sync.snapshotCurrentChildren();
    final out = <SKey, List<IKey>>{};
    for (final entry in raw.entries) {
      final parent = entry.key;
      if (parent is! SectionKey<SKey, IKey>) {
        continue;
      }
      out[parent.value] = <IKey>[
        for (final c in entry.value)
          if (c is ItemKey<SKey, IKey>) c.value,
      ];
    }
    return out;
  }

  Set<SKey> debugSnapshotRememberedSectionKeys() {
    final out = <SKey>{};
    for (final k in _sync.snapshotRememberedKeys()) {
      if (k is SectionKey<SKey, IKey>) {
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
  void setSections(
    Iterable<SectionInput<SKey, IKey, Section, Item>> sections, {
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
    final desired = <TreeNode<SecKey<SKey, IKey>, SecPayload<Section, Item>>>[
      for (final s in list)
        TreeNode(
          key: SectionKey<SKey, IKey>(s.key),
          data: SectionPayload<Section, Item>(s.section),
        ),
    ];
    final byKey = <SKey, SectionInput<SKey, IKey, Section, Item>>{
      for (final s in list) s.key: s,
    };
    _sync.syncRoots(
      desired,
      childrenOf: (k) {
        if (k is! SectionKey<SKey, IKey>) {
          return const [];
        }
        final input = byKey[k.value];
        if (input == null) {
          return const [];
        }
        return <TreeNode<SecKey<SKey, IKey>, SecPayload<Section, Item>>>[
          for (final i in input.items)
            TreeNode(
              key: ItemKey<SKey, IKey>(i.key),
              data: ItemPayload<Section, Item>(i.item),
            ),
        ];
      },
      animate: animate,
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Public API — section-scoped
  // ──────────────────────────────────────────────────────────────────

  void addSection(
    SectionInput<SKey, IKey, Section, Item> section, {
    int? index,
    bool animate = true,
  }) {
    _checkNotDisposed();
    _tree.runBatch(() {
      _tree.insertRoot(
        TreeNode(
          key: SectionKey<SKey, IKey>(section.key),
          data: SectionPayload<Section, Item>(section.section),
        ),
        index: index,
        animate: animate,
      );
      if (section.items.isNotEmpty) {
        _tree.setChildren(
          SectionKey<SKey, IKey>(section.key),
          <TreeNode<SecKey<SKey, IKey>, SecPayload<Section, Item>>>[
            for (final i in section.items)
              TreeNode(
                key: ItemKey<SKey, IKey>(i.key),
                data: ItemPayload<Section, Item>(i.item),
              ),
          ],
        );
      }
    });
  }

  void removeSection(SKey key, {bool animate = true}) {
    _checkNotDisposed();
    _requireSection(key, "removeSection");
    _tree.remove(key: SectionKey<SKey, IKey>(key), animate: animate);
  }

  void updateSection(SKey key, Section section) {
    _checkNotDisposed();
    _requireSection(key, "updateSection");
    _tree.updateNode(
      TreeNode(
        key: SectionKey<SKey, IKey>(key),
        data: SectionPayload<Section, Item>(section),
      ),
    );
  }

  void setItems(
    SKey sectionKey,
    Iterable<ItemInput<IKey, Item>> items, {
    bool animate = true,
  }) {
    _checkNotDisposed();
    _requireSection(sectionKey, "setItems");
    // Re-initialize tracking so the diff is computed against the actual
    // current state — see [setSections] for the rationale.
    _sync.initializeTracking();
    final desired = <TreeNode<SecKey<SKey, IKey>, SecPayload<Section, Item>>>[
      for (final i in items)
        TreeNode(
          key: ItemKey<SKey, IKey>(i.key),
          data: ItemPayload<Section, Item>(i.item),
        ),
    ];
    _sync.syncChildren(
      SectionKey<SKey, IKey>(sectionKey),
      desired,
      animate: animate,
    );
  }

  void reorderSections(List<SKey> orderedKeys) {
    _checkNotDisposed();
    _tree.reorderRoots(<SecKey<SKey, IKey>>[
      for (final k in orderedKeys) SectionKey<SKey, IKey>(k),
    ]);
  }

  void moveSection(SKey key, int toIndex) {
    _checkNotDisposed();
    _requireSection(key, "moveSection");
    if (_tree.isPendingDeletion(SectionKey<SKey, IKey>(key))) {
      _throwMissing("moveSection", "section $key is being removed");
    }
    // Use the LIVE list — `reorderSections` → `_tree.reorderRoots`
    // validates against the live root set (excludes pending-deletion).
    // The previous full-list form would build a proposed order
    // including pending-deletion siblings and trip the validation when
    // a sibling section was mid-exit-animation.
    final order = liveSections..remove(key);
    final clamped = toIndex.clamp(0, order.length);
    order.insert(clamped, key);
    reorderSections(order);
  }

  // ──────────────────────────────────────────────────────────────────
  // Public API — item-scoped
  // ──────────────────────────────────────────────────────────────────

  void addItem(
    SKey sectionKey,
    ItemInput<IKey, Item> item, {
    int? index,
    bool animate = true,
  }) {
    _checkNotDisposed();
    _requireSection(sectionKey, "addItem");
    _tree.insert(
      parentKey: SectionKey<SKey, IKey>(sectionKey),
      node: TreeNode(
        key: ItemKey<SKey, IKey>(item.key),
        data: ItemPayload<Section, Item>(item.item),
      ),
      index: index,
      animate: animate,
    );
  }

  void removeItem(IKey key, {bool animate = true}) {
    _checkNotDisposed();
    _requireItem(key, "removeItem");
    _tree.remove(key: ItemKey<SKey, IKey>(key), animate: animate);
  }

  void updateItem(IKey key, Item item) {
    _checkNotDisposed();
    _requireItem(key, "updateItem");
    _tree.updateNode(
      TreeNode(
        key: ItemKey<SKey, IKey>(key),
        data: ItemPayload<Section, Item>(item),
      ),
    );
  }

  void moveItem(IKey key, {required SKey toSection, int? index}) {
    _checkNotDisposed();
    _requireItem(key, "moveItem");
    _requireSection(toSection, "moveItem(toSection)");
    _tree.moveNode(
      ItemKey<SKey, IKey>(key),
      SectionKey<SKey, IKey>(toSection),
      index: index,
    );
  }

  void reorderItems(SKey sectionKey, List<IKey> orderedKeys) {
    _checkNotDisposed();
    _requireSection(sectionKey, "reorderItems");
    _tree.reorderChildren(
      SectionKey<SKey, IKey>(sectionKey),
      <SecKey<SKey, IKey>>[for (final k in orderedKeys) ItemKey<SKey, IKey>(k)],
    );
  }

  void moveItemInSection(IKey key, int toIndex) {
    _checkNotDisposed();
    _requireItem(key, "moveItemInSection");
    if (_tree.isPendingDeletion(ItemKey<SKey, IKey>(key))) {
      _throwMissing("moveItemInSection", "item $key is being removed");
    }
    final parentKey = sectionOf(key);
    if (parentKey == null) {
      _throwMissing("moveItemInSection", "item $key has no parent section");
    }
    // Use the LIVE list — `reorderItems` → `_tree.reorderChildren`
    // validates against the live child set (excludes pending-deletion).
    // The previous full-list form built a proposed order including
    // pending-deletion siblings and tripped the validation when an
    // item sibling was mid-exit-animation.
    final siblings = liveItemsOf(parentKey as SKey)..remove(key);
    final clamped = toIndex.clamp(0, siblings.length);
    siblings.insert(clamped, key);
    reorderItems(parentKey, siblings);
  }

  // ──────────────────────────────────────────────────────────────────
  // Public API — expansion
  // ──────────────────────────────────────────────────────────────────

  void expandSection(SKey key, {bool animate = true}) {
    _checkNotDisposed();
    _requireSection(key, "expandSection");
    _tree.expand(key: SectionKey<SKey, IKey>(key), animate: animate);
  }

  void collapseSection(SKey key, {bool animate = true}) {
    _checkNotDisposed();
    _requireSection(key, "collapseSection");
    _tree.collapse(key: SectionKey<SKey, IKey>(key), animate: animate);
  }

  void toggleSection(SKey key, {bool animate = true}) {
    _checkNotDisposed();
    _requireSection(key, "toggleSection");
    _tree.toggle(key: SectionKey<SKey, IKey>(key), animate: animate);
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
  // ──────────────────────────────────────────────────────────────────

  bool hasSection(SKey key) {
    _checkNotDisposed();
    return _tree.getNodeData(SectionKey<SKey, IKey>(key)) != null;
  }

  bool hasItem(IKey key) {
    _checkNotDisposed();
    return _tree.getNodeData(ItemKey<SKey, IKey>(key)) != null;
  }

  Section? getSection(SKey key) {
    _checkNotDisposed();
    final node = _tree.getNodeData(SectionKey<SKey, IKey>(key));
    if (node == null) {
      return null;
    }
    final data = node.data;
    assert(
      data is SectionPayload<Section, Item>,
      "Node at SectionKey($key) is not a SectionPayload — tree invariant violated",
    );
    return (data as SectionPayload<Section, Item>).value;
  }

  Item? getItem(IKey key) {
    _checkNotDisposed();
    final node = _tree.getNodeData(ItemKey<SKey, IKey>(key));
    if (node == null) {
      return null;
    }
    final data = node.data;
    assert(
      data is ItemPayload<Section, Item>,
      "Node at ItemKey($key) is not an ItemPayload — tree invariant violated",
    );
    return (data as ItemPayload<Section, Item>).value;
  }

  SKey? sectionOf(IKey key) {
    _checkNotDisposed();
    final parent = _tree.getParent(ItemKey<SKey, IKey>(key));
    if (parent == null) {
      return null;
    }
    assert(
      parent is SectionKey<SKey, IKey>,
      "Item $key has a non-section parent — tree invariant violated",
    );
    return (parent as SectionKey<SKey, IKey>).value;
  }

  /// Section keys in render order. Returns `[]` when empty.
  ///
  /// Includes sections that are mid-exit-animation (pending-deletion).
  /// Use [liveSections] when you need only sections that aren't being
  /// removed — e.g., when constructing a list for `reorderSections`,
  /// which validates against the live set.
  List<SKey> get sections {
    _checkNotDisposed();
    final raw = _tree.rootKeys;
    return <SKey>[
      for (final k in raw)
        if (_assertIsSection(k)) (k as SectionKey<SKey, IKey>).value,
    ];
  }

  /// Section keys in render order, EXCLUDING sections currently mid-
  /// exit-animation. Returns `[]` when no live sections exist.
  ///
  /// This is the input shape `reorderSections` expects.
  List<SKey> get liveSections {
    _checkNotDisposed();
    final raw = _tree.liveRootKeys;
    return <SKey>[
      for (final k in raw)
        if (_assertIsSection(k)) (k as SectionKey<SKey, IKey>).value,
    ];
  }

  /// Item keys for [sectionKey] in render order. Returns `[]` when the
  /// section does not exist or has no items — call [hasSection] to
  /// disambiguate if needed.
  ///
  /// Includes items that are mid-exit-animation (pending-deletion).
  /// Use [liveItemsOf] when you need only items that aren't being
  /// removed — e.g., when constructing a list for `reorderItems`,
  /// which validates against the live set.
  List<IKey> itemsOf(SKey sectionKey) {
    _checkNotDisposed();
    final children = _tree.getChildren(SectionKey<SKey, IKey>(sectionKey));
    if (children.isEmpty) {
      return const [];
    }
    return <IKey>[
      for (final k in children)
        if (_assertIsItem(k)) (k as ItemKey<SKey, IKey>).value,
    ];
  }

  /// Item keys for [sectionKey] in render order, EXCLUDING items
  /// currently mid-exit-animation. Returns `[]` when no live items
  /// exist (or the section is unknown).
  ///
  /// This is the input shape `reorderItems` expects.
  List<IKey> liveItemsOf(SKey sectionKey) {
    _checkNotDisposed();
    final children = _tree.getLiveChildren(SectionKey<SKey, IKey>(sectionKey));
    if (children.isEmpty) {
      return const [];
    }
    return <IKey>[
      for (final k in children)
        if (_assertIsItem(k)) (k as ItemKey<SKey, IKey>).value,
    ];
  }

  bool isExpanded(SKey key) {
    _checkNotDisposed();
    return _tree.isExpanded(SectionKey<SKey, IKey>(key));
  }

  /// Number of items currently belonging to [sectionKey], regardless
  /// of expansion state. Returns `0` for unknown sections.
  int itemCount(SKey sectionKey) {
    _checkNotDisposed();
    return _tree.getChildCount(SectionKey<SKey, IKey>(sectionKey));
  }

  /// Position of [itemKey] among its section's children in
  /// **live-list space** (skipping pending-deletion siblings). Returns
  /// `-1` when [itemKey] is not present, is itself pending-deletion, or
  /// is not an item.
  ///
  /// Mirrors what `_buildItem` in the widget passes as
  /// `ItemView.indexInSection`, so callers — including the
  /// `view.watch(...)` selective-rebuild widget — can compute the same
  /// value without scanning a freshly-allocated `itemsOf(sectionKey)`
  /// list.
  int indexOfItem(IKey itemKey) {
    _checkNotDisposed();
    return _tree.getIndexInParent(ItemKey<SKey, IKey>(itemKey));
  }

  // ──────────────────────────────────────────────────────────────────
  // Public API — batching
  // ──────────────────────────────────────────────────────────────────

  /// Coalesces structural notifications across the mutations performed
  /// inside [body] into a single post-batch refresh. Delegates to the
  /// underlying [TreeController.runBatch].
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
    _sync.dispose();
    _tree.dispose();
  }

  // ──────────────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────────────

  void _checkNotDisposed() {
    assert(!_disposed, "SectionedListController used after dispose()");
  }

  void _requireSection(SKey key, String method) {
    if (_tree.getNodeData(SectionKey<SKey, IKey>(key)) == null) {
      _throwMissing(method, "no section with key $key");
    }
  }

  void _requireItem(IKey key, String method) {
    if (_tree.getNodeData(ItemKey<SKey, IKey>(key)) == null) {
      _throwMissing(method, "no item with key $key");
    }
  }

  Never _throwMissing(String method, String detail) {
    final message = "SectionedListController.$method: $detail";
    assert(false, message);
    throw StateError(message);
  }

  bool _assertIsSection(SecKey<SKey, IKey> k) {
    assert(
      k is SectionKey<SKey, IKey>,
      "Expected a SectionKey at root level but found $k — "
      "tree invariant violated",
    );
    return k is SectionKey<SKey, IKey>;
  }

  bool _assertIsItem(SecKey<SKey, IKey> k) {
    assert(
      k is ItemKey<SKey, IKey>,
      "Expected an ItemKey under a section but found $k — "
      "tree invariant violated",
    );
    return k is ItemKey<SKey, IKey>;
  }
}
