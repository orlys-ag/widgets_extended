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

/// Controller for a [SectionedSliverList].
///
/// Owns the imperative API (`addItem`, `moveItem`, `setItems`,
/// `expandSection`, ...). When supplied to a `SectionedSliverList`
/// constructed via the `.controlled` named constructor, the widget
/// binds to it and renders whatever state the controller currently
/// holds. The widget never reads section/item data from props in that
/// mode — the controller IS the source of truth.
///
/// In `default` / `.fromMap` mode the widget creates and disposes its
/// own internal controller; the user never sees one.
///
/// Lifetime: external controllers must be disposed by their owner.
/// Internally-created controllers are disposed by the widget.
///
/// A controller is designed to drive exactly one mounted widget at a
/// time. Mounting two widgets against the same controller asserts in
/// debug.
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
class SectionedListController<K extends Object, Section, Item>
    implements Listenable {
  SectionedListController({
    required TickerProvider vsync,
    required this.sectionKeyOf,
    required this.itemKeyOf,
    Duration animationDuration = const Duration(milliseconds: 300),
    Curve animationCurve = Curves.easeInOut,
    double itemIndent = 0.0,
    bool preserveExpansion = true,
  }) : _tree = TreeController<SecKey<K>, SecPayload<Section, Item>>(
         vsync: vsync,
         animationDuration: animationDuration,
         animationCurve: animationCurve,
         indentWidth: itemIndent,
       ),
       _preserveExpansion = preserveExpansion {
    _sync = TreeSyncController<SecKey<K>, SecPayload<Section, Item>>(
      treeController: _tree,
      preserveExpansion: preserveExpansion,
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
  TreeController<SecKey<K>, SecPayload<Section, Item>> get treeController {
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
  ///
  /// This is a documented part of the public surface: a
  /// `SectionedListController` may drive at most one mounted
  /// `SectionedSliverList.controlled` widget at a time.
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

  // ──────────────────────────────────────────────────────────────────
  // Configuration setters
  // ──────────────────────────────────────────────────────────────────

  set animationDuration(Duration value) {
    _checkNotDisposed();
    _tree.animationDuration = value;
  }

  Duration get animationDuration {
    _checkNotDisposed();
    return _tree.animationDuration;
  }

  set animationCurve(Curve value) {
    _checkNotDisposed();
    _tree.animationCurve = value;
  }

  Curve get animationCurve {
    _checkNotDisposed();
    return _tree.animationCurve;
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
      preserveExpansion: value,
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

  Set<K> debugSnapshotRememberedSectionKeys() {
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
    final order = sectionKeys..remove(sectionKey);
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

  /// Reparents [itemKey] under [toSection]. When [index] is null, the
  /// item is appended to [toSection]'s children.
  ///
  /// No `animate` parameter: the underlying [TreeController.moveNode]
  /// is a repositioning op, not an insert/remove; nothing animates.
  void moveItem(K itemKey, {required K toSection, int? index}) {
    _checkNotDisposed();
    _requireItem(itemKey, "moveItem");
    _requireSection(toSection, "moveItem(toSection)");
    _tree.moveNode(ItemKey<K>(itemKey), SectionKey<K>(toSection), index: index);
  }

  void reorderItems(K sectionKey, List<K> orderedKeys) {
    _checkNotDisposed();
    _requireSection(sectionKey, "reorderItems");
    _tree.reorderChildren(SectionKey<K>(sectionKey), <SecKey<K>>[
      for (final k in orderedKeys) ItemKey<K>(k),
    ]);
  }

  void moveItemInSection(K itemKey, int toIndex) {
    _checkNotDisposed();
    _requireItem(itemKey, "moveItemInSection");
    if (_tree.isPendingDeletion(ItemKey<K>(itemKey))) {
      _throwMissing("moveItemInSection", "item $itemKey is being removed");
    }
    final parentKey = sectionOf(itemKey);
    if (parentKey == null) {
      _throwMissing("moveItemInSection", "item $itemKey has no parent section");
    }
    // Use the LIVE list — `reorderItems` → `_tree.reorderChildren`
    // validates against the live child set (excludes pending-deletion).
    final siblings = itemKeysOf(parentKey)..remove(itemKey);
    final clamped = toIndex.clamp(0, siblings.length);
    siblings.insert(clamped, itemKey);
    reorderItems(parentKey, siblings);
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
  // Default queries return LIVE entries (excluding pending-deletion).
  // The `all*` variants include pending-deletion as escape hatches.
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

  /// Section payloads in render order, EXCLUDING sections currently
  /// mid-exit-animation. This is the input shape `reorderSections`
  /// implicitly expects (via the keys returned by [sectionKeys]).
  List<Section> get sections {
    _checkNotDisposed();
    final live = _tree.liveRootKeys;
    final out = <Section>[];
    for (final k in live) {
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

  /// Section keys in render order, EXCLUDING pending-deletion.
  List<K> get sectionKeys {
    _checkNotDisposed();
    return <K>[
      for (final k in _tree.liveRootKeys)
        if (_assertIsSection(k)) (k as SectionKey<K>).value,
    ];
  }

  /// All section payloads in render order, INCLUDING those currently
  /// mid-exit-animation. Escape hatch for callers that need to
  /// introspect mid-animation state.
  List<Section> get allSections {
    _checkNotDisposed();
    final raw = _tree.rootKeys;
    final out = <Section>[];
    for (final k in raw) {
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

  /// All section keys in render order, INCLUDING pending-deletion.
  List<K> get allSectionKeys {
    _checkNotDisposed();
    return <K>[
      for (final k in _tree.rootKeys)
        if (_assertIsSection(k)) (k as SectionKey<K>).value,
    ];
  }

  /// Item payloads under [sectionKey] in render order, EXCLUDING
  /// pending-deletion. Returns `[]` for unknown sections.
  List<Item> itemsOf(K sectionKey) {
    _checkNotDisposed();
    final children = _tree.getLiveChildren(SectionKey<K>(sectionKey));
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

  /// Item keys under [sectionKey] in render order, EXCLUDING
  /// pending-deletion.
  List<K> itemKeysOf(K sectionKey) {
    _checkNotDisposed();
    final children = _tree.getLiveChildren(SectionKey<K>(sectionKey));
    if (children.isEmpty) {
      return const [];
    }
    return <K>[
      for (final k in children)
        if (_assertIsItem(k)) (k as ItemKey<K>).value,
    ];
  }

  /// All item payloads under [sectionKey] in render order, INCLUDING
  /// pending-deletion.
  List<Item> allItemsOf(K sectionKey) {
    _checkNotDisposed();
    final children = _tree.getChildren(SectionKey<K>(sectionKey));
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

  /// All item keys under [sectionKey] in render order, INCLUDING
  /// pending-deletion.
  List<K> allItemKeysOf(K sectionKey) {
    _checkNotDisposed();
    final children = _tree.getChildren(SectionKey<K>(sectionKey));
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
