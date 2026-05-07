/// Views handed to `headerBuilder` / `itemBuilder` callbacks, plus the
/// selective-rebuild helpers (`SectionView.watch`, `ItemView.watch`).
library;

import 'package:flutter/widgets.dart';

import 'sectioned_list_controller.dart';

/// Rich view of a visible section header passed to a header builder.
class SectionView<K extends Object, Section, Item> {
  const SectionView({
    required this.key,
    required this.section,
    required this.itemCount,
    required this.isExpanded,
    required this.isCollapsible,
    required this.controller,
  });

  /// Unique identifier for this section.
  final K key;

  /// User payload for the section header.
  final Section section;

  /// Total items currently belonging to this section, regardless of
  /// expansion state. Visible count is `isExpanded ? itemCount : 0`.
  final int itemCount;

  /// Whether the section is currently expanded.
  final bool isExpanded;

  /// Whether the user can toggle this section's expansion. `false`
  /// when the parent widget was created with `collapsible: false`.
  ///
  /// Advisory only — the [expand] / [collapse] / [toggle] shortcuts on
  /// this view always pass through to the controller regardless of this
  /// flag. Use it to decide whether to render a chevron, not to gate
  /// state mutations.
  final bool isCollapsible;

  /// The controller backing this view, available as an escape hatch.
  /// Convenience methods on this view delegate to the controller.
  final SectionedListController<K, Section, Item> controller;

  /// Expands this section.
  void expand({bool animate = true}) {
    controller.expandSection(key, animate: animate);
  }

  /// Collapses this section.
  void collapse({bool animate = true}) {
    controller.collapseSection(key, animate: animate);
  }

  /// Toggles expansion.
  void toggle({bool animate = true}) {
    controller.toggleSection(key, animate: animate);
  }

  /// Replaces this section's payload. Asserts that the section still
  /// exists.
  void update(Section section) {
    controller.updateSection(key, section);
  }

  /// Removes this section (and all its items).
  void remove({bool animate = true}) {
    controller.removeSection(key, animate: animate);
  }

  /// Adds [item] under this section. Forwards to
  /// [SectionedListController.addItem].
  void addItem(Item item, {int? index, bool animate = true}) {
    controller.addItem(item, toSection: key, index: index, animate: animate);
  }

  /// Selectively rebuilds [builder] when this section's state changes:
  ///   - expand/collapse
  ///   - section payload (via `controller.updateSection`)
  ///   - item count (items added or removed under this section)
  ///
  /// The most common reason to use [watch] in a header is to keep a
  /// "X items" badge in sync as items churn under the section.
  Widget watch({
    required Widget Function(
      BuildContext context,
      SectionView<K, Section, Item> view,
    )
    builder,
    Key? widgetKey,
  }) {
    return _SectionViewListener<K, Section, Item>(
      key: widgetKey,
      controller: controller,
      sectionKey: key,
      isCollapsible: isCollapsible,
      builder: builder,
    );
  }
}

/// Rich view of a visible item passed to an item builder.
class ItemView<K extends Object, Section, Item> {
  const ItemView({
    required this.key,
    required this.item,
    required this.sectionKey,
    required this.section,
    required this.indexInSection,
    required this.controller,
  });

  /// Unique identifier for this item.
  final K key;

  /// User payload.
  final Item item;

  /// Identifier of the section this item belongs to.
  final K sectionKey;

  /// Section payload, resolved for convenience.
  final Section section;

  /// Position among siblings in the section, 0-based, in live-list
  /// space (skipping pending-deletion siblings).
  final int indexInSection;

  /// The controller backing this view.
  final SectionedListController<K, Section, Item> controller;

  /// Replaces this item's payload. Asserts that the item still exists.
  void update(Item item) {
    controller.updateItem(key, item);
  }

  /// Removes this item.
  void remove({bool animate = true}) {
    controller.removeItem(key, animate: animate);
  }

  /// Moves this item to [section] and/or [index].
  ///
  /// Dispatches to the controller as follows:
  ///
  ///   • `section != null, index != null`
  ///       → [SectionedListController.moveItem] with both args
  ///   • `section != null, index == null`
  ///       → [SectionedListController.moveItem] (appends to section)
  ///   • `section == null, index != null`
  ///       → [SectionedListController.moveItemInSection]
  ///   • `section == null, index == null`
  ///       → no-op
  ///
  /// No `animate` parameter: the underlying [TreeController.moveNode] /
  /// [TreeController.reorderChildren] are repositioning ops — nothing
  /// animates. Matches the controller-level signatures.
  void moveTo({K? section, int? index}) {
    if (section != null) {
      controller.moveItem(key, toSection: section, index: index);
    } else if (index != null) {
      controller.moveItemInSection(key, index);
    }
    // both null → no-op.
  }

  /// Selectively rebuilds [builder] when this item's payload changes
  /// via `controller.updateItem`. Does NOT trigger on indexInSection
  /// changes (e.g., a sibling moves) or on reparenting — those are
  /// structural and the row is rebuilt by the underlying SliverTree
  /// as part of normal layout.
  Widget watch({
    required Widget Function(
      BuildContext context,
      ItemView<K, Section, Item> view,
    )
    builder,
    Key? widgetKey,
  }) {
    return _ItemViewListener<K, Section, Item>(
      key: widgetKey,
      controller: controller,
      itemKey: key,
      sectionKey: sectionKey,
      builder: builder,
    );
  }
}

/// Listener widget for [SectionView.watch]. Subscribes to the
/// controller's structural channel for expand/collapse + item-count
/// changes, and to the typed section-payload channel for payload
/// updates. Filters by [sectionKey] so only the watched section
/// triggers a rebuild.
class _SectionViewListener<K extends Object, Section, Item>
    extends StatefulWidget {
  const _SectionViewListener({
    required this.controller,
    required this.sectionKey,
    required this.isCollapsible,
    required this.builder,
    super.key,
  });

  final SectionedListController<K, Section, Item> controller;
  final K sectionKey;
  final bool isCollapsible;
  final Widget Function(
    BuildContext context,
    SectionView<K, Section, Item> view,
  )
  builder;

  @override
  State<_SectionViewListener<K, Section, Item>> createState() {
    return _SectionViewListenerState<K, Section, Item>();
  }
}

class _SectionViewListenerState<K extends Object, Section, Item>
    extends State<_SectionViewListener<K, Section, Item>> {
  late bool _isExpanded;
  late int _itemCount;

  void _onStructural() {
    final nextExpanded = widget.controller.isExpanded(widget.sectionKey);
    final nextCount = widget.controller.itemCount(widget.sectionKey);
    if (nextExpanded != _isExpanded || nextCount != _itemCount) {
      setState(() {
        _isExpanded = nextExpanded;
        _itemCount = nextCount;
      });
    }
  }

  void _onSectionPayload(K key) {
    if (key != widget.sectionKey) {
      return;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _resnapshot() {
    _isExpanded = widget.controller.isExpanded(widget.sectionKey);
    _itemCount = widget.controller.itemCount(widget.sectionKey);
  }

  @override
  void initState() {
    super.initState();
    _resnapshot();
    widget.controller.addListener(_onStructural);
    widget.controller.addSectionPayloadListener(_onSectionPayload);
  }

  @override
  void didUpdateWidget(
    _SectionViewListener<K, Section, Item> oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onStructural);
      oldWidget.controller.removeSectionPayloadListener(_onSectionPayload);
      widget.controller.addListener(_onStructural);
      widget.controller.addSectionPayloadListener(_onSectionPayload);
      _resnapshot();
    } else if (oldWidget.sectionKey != widget.sectionKey) {
      _resnapshot();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStructural);
    widget.controller.removeSectionPayloadListener(_onSectionPayload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.controller.getSection(widget.sectionKey);
    if (section == null) {
      return const SizedBox.shrink();
    }
    final view = SectionView<K, Section, Item>(
      key: widget.sectionKey,
      section: section,
      itemCount: _itemCount,
      isExpanded: _isExpanded,
      isCollapsible: widget.isCollapsible,
      controller: widget.controller,
    );
    return widget.builder(context, view);
  }
}

/// Listener widget for [ItemView.watch]. Subscribes only to the typed
/// item-payload channel and filters by [itemKey].
class _ItemViewListener<K extends Object, Section, Item>
    extends StatefulWidget {
  const _ItemViewListener({
    required this.controller,
    required this.itemKey,
    required this.sectionKey,
    required this.builder,
    super.key,
  });

  final SectionedListController<K, Section, Item> controller;
  final K itemKey;
  final K sectionKey;
  final Widget Function(
    BuildContext context,
    ItemView<K, Section, Item> view,
  )
  builder;

  @override
  State<_ItemViewListener<K, Section, Item>> createState() {
    return _ItemViewListenerState<K, Section, Item>();
  }
}

class _ItemViewListenerState<K extends Object, Section, Item>
    extends State<_ItemViewListener<K, Section, Item>> {
  void _onItemPayload(K key) {
    if (key != widget.itemKey) {
      return;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addItemPayloadListener(_onItemPayload);
  }

  @override
  void didUpdateWidget(_ItemViewListener<K, Section, Item> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeItemPayloadListener(_onItemPayload);
      widget.controller.addItemPayloadListener(_onItemPayload);
    }
  }

  @override
  void dispose() {
    widget.controller.removeItemPayloadListener(_onItemPayload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.controller.getItem(widget.itemKey);
    final section = widget.controller.getSection(widget.sectionKey);
    if (item == null || section == null) {
      return const SizedBox.shrink();
    }
    // Use the controller's LIVE-list index (mirrors what _buildItem
    // passes to the outer itemBuilder).
    final indexInSection = widget.controller.indexOfItem(widget.itemKey);
    final view = ItemView<K, Section, Item>(
      key: widget.itemKey,
      item: item,
      sectionKey: widget.sectionKey,
      section: section,
      indexInSection: indexInSection,
      controller: widget.controller,
    );
    return widget.builder(context, view);
  }
}
