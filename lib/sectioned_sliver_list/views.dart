/// Views handed to `headerBuilder` / `itemBuilder` callbacks, plus the
/// selective-rebuild helpers (`SectionView.watch`, `ItemView.watch`).
library;

import 'package:flutter/widgets.dart';

import 'sectioned_list_controller.dart';

/// Rich view of a visible section header passed to a header builder.
class SectionView<SKey, IKey, Section, Item> {
  const SectionView({
    required this.key,
    required this.section,
    required this.itemCount,
    required this.isExpanded,
    required this.isCollapsible,
    required this.controller,
  });

  /// Unique identifier for this section.
  final SKey key;

  /// User payload for the section header.
  final Section section;

  /// Total items currently belonging to this section, regardless of
  /// expansion state. Visible count is `isExpanded ? itemCount : 0`.
  final int itemCount;

  /// Whether the section is currently expanded.
  final bool isExpanded;

  /// Whether the user can toggle this section's expansion. `false`
  /// when the parent widget was created with `collapsible: false`.
  final bool isCollapsible;

  /// The controller backing this view, available as an escape hatch.
  /// Convenience methods on this view delegate to the controller.
  final SectionedListController<SKey, IKey, Section, Item> controller;

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
      SectionView<SKey, IKey, Section, Item> view,
    )
    builder,
    Key? widgetKey,
  }) {
    return _SectionViewListener<SKey, IKey, Section, Item>(
      key: widgetKey,
      controller: controller,
      sectionKey: key,
      isCollapsible: isCollapsible,
      builder: builder,
    );
  }
}

/// Rich view of a visible item passed to an item builder.
class ItemView<SKey, IKey, Section, Item> {
  const ItemView({
    required this.key,
    required this.item,
    required this.sectionKey,
    required this.section,
    required this.indexInSection,
    required this.controller,
  });

  /// Unique identifier for this item.
  final IKey key;

  /// User payload.
  final Item item;

  /// Identifier of the section this item belongs to.
  final SKey sectionKey;

  /// Section payload, resolved for convenience.
  final Section section;

  /// Position among siblings in the section, 0-based.
  final int indexInSection;

  /// The controller backing this view.
  final SectionedListController<SKey, IKey, Section, Item> controller;

  /// Selectively rebuilds [builder] when this item's payload changes
  /// via `controller.updateItem`. Does NOT trigger on indexInSection
  /// changes (e.g., a sibling moves) or on reparenting — those are
  /// structural and the row is rebuilt by the underlying SliverTree
  /// as part of normal layout.
  Widget watch({
    required Widget Function(
      BuildContext context,
      ItemView<SKey, IKey, Section, Item> view,
    )
    builder,
    Key? widgetKey,
  }) {
    return _ItemViewListener<SKey, IKey, Section, Item>(
      key: widgetKey,
      controller: controller,
      itemKey: key,
      sectionKey: sectionKey,
      builder: builder,
    );
  }
}

class _SectionViewListener<SKey, IKey, Section, Item> extends StatefulWidget {
  const _SectionViewListener({
    required this.controller,
    required this.sectionKey,
    required this.isCollapsible,
    required this.builder,
    super.key,
  });

  final SectionedListController<SKey, IKey, Section, Item> controller;
  final SKey sectionKey;
  final bool isCollapsible;
  final Widget Function(
    BuildContext context,
    SectionView<SKey, IKey, Section, Item> view,
  )
  builder;

  @override
  State<_SectionViewListener<SKey, IKey, Section, Item>> createState() {
    return _SectionViewListenerState<SKey, IKey, Section, Item>();
  }
}

class _SectionViewListenerState<SKey, IKey, Section, Item>
    extends State<_SectionViewListener<SKey, IKey, Section, Item>> {
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

  void _onPayload(Object? key) {
    // The underlying controller fires this with the wrapped SecKey, but
    // we cannot inspect it without exposing the internal types. Trigger
    // a rebuild on any payload notification — over-rebuilding is
    // acceptable here because the per-section header is cheap and
    // payload notifications are rare.
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
    widget.controller.treeController.addListener(_onStructural);
    widget.controller.treeController.addNodeDataListener(_onPayload);
  }

  @override
  void didUpdateWidget(
    _SectionViewListener<SKey, IKey, Section, Item> oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.treeController
        ..removeListener(_onStructural)
        ..removeNodeDataListener(_onPayload);
      widget.controller.treeController
        ..addListener(_onStructural)
        ..addNodeDataListener(_onPayload);
      _resnapshot();
    } else if (oldWidget.sectionKey != widget.sectionKey) {
      _resnapshot();
    }
  }

  @override
  void dispose() {
    widget.controller.treeController
      ..removeListener(_onStructural)
      ..removeNodeDataListener(_onPayload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.controller.getSection(widget.sectionKey);
    if (section == null) {
      return const SizedBox.shrink();
    }
    final view = SectionView<SKey, IKey, Section, Item>(
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

class _ItemViewListener<SKey, IKey, Section, Item> extends StatefulWidget {
  const _ItemViewListener({
    required this.controller,
    required this.itemKey,
    required this.sectionKey,
    required this.builder,
    super.key,
  });

  final SectionedListController<SKey, IKey, Section, Item> controller;
  final IKey itemKey;
  final SKey sectionKey;
  final Widget Function(
    BuildContext context,
    ItemView<SKey, IKey, Section, Item> view,
  )
  builder;

  @override
  State<_ItemViewListener<SKey, IKey, Section, Item>> createState() {
    return _ItemViewListenerState<SKey, IKey, Section, Item>();
  }
}

class _ItemViewListenerState<SKey, IKey, Section, Item>
    extends State<_ItemViewListener<SKey, IKey, Section, Item>> {
  void _onPayload(Object? key) {
    // Same conservative rule as _SectionViewListener: rebuild on any
    // payload notification. The wrapped SecKey identity is private and
    // we cannot filter on it from outside.
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.treeController.addNodeDataListener(_onPayload);
  }

  @override
  void didUpdateWidget(_ItemViewListener<SKey, IKey, Section, Item> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.treeController.removeNodeDataListener(_onPayload);
      widget.controller.treeController.addNodeDataListener(_onPayload);
    }
  }

  @override
  void dispose() {
    widget.controller.treeController.removeNodeDataListener(_onPayload);
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
    // passes to the outer itemBuilder). The previous
    // `itemsOf(sectionKey).indexOf(itemKey)` returned the FULL-list
    // index — including pending-deletion siblings — so the inner
    // builder disagreed with the outer about a row's position whenever
    // a sibling was mid-exit. It also avoids the per-build O(N)
    // allocation of the items list.
    final indexInSection = widget.controller.indexOfItem(widget.itemKey);
    final view = ItemView<SKey, IKey, Section, Item>(
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
