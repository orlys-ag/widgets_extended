/// Header + items convenience sliver, built on top of [SliverTree].
///
/// Models a strict 2-level structure (sections containing items, items
/// have no children) with separate types and builders for each level,
/// animated insert/remove/reparent, and sticky headers.
///
/// Type parameters: `<K extends Object, Section, Item>`. Section and
/// item key domains share a single user-facing parameter `K` and are
/// kept disjoint internally via the wrapper types in `_internal_keys.dart`.
///
/// Two constructors, each with a single source of truth:
///
/// - default — pull-model declarative form. The widget owns an internal
///   controller and the `sections` / `itemsOf` props are authoritative:
///   every rebuild re-runs the diff against them and animates the
///   transition.
///   ```dart
///   SectionedSliverList<String, Folder, File>(
///     sections: folders,
///     itemsOf: (f) => f.files,
///     sectionKeyOf: (f) => f.id,
///     itemKeyOf: (f) => f.id,
///     headerBuilder: (ctx, s) => FolderHeader(s.section),
///     itemBuilder: (ctx, i) => FileTile(i.item),
///   )
///   ```
///
/// - `.controlled` — push-model imperative form. A caller-owned
///   [SectionedListController] is the authoritative state; the widget
///   only renders it and never diffs. Use this when the list itself
///   owns its state and is mutated imperatively.
///   ```dart
///   SectionedSliverList.controlled(
///     controller: myController,
///     headerBuilder: ..., itemBuilder: ...,
///   )
///   ```
///
/// Internally this is a thin dispatcher: the declarative form layers a
/// prop-diffing [State] on top of the controlled renderer, so neither
/// path carries mode branching. Switching constructors at the same slot
/// is handled by the framework — the two impls have distinct types, so
/// Flutter tears one down and mounts the other.
library;

import 'package:flutter/widgets.dart';

import '../sliver_tree/sliver_tree.dart';
import '_internal_keys.dart';
import 'sectioned_list_controller.dart';
import 'views.dart';

/// Builds a header widget for a visible section.
typedef SectionHeaderBuilder<K extends Object, Section, Item> =
    Widget Function(BuildContext context, SectionView<K, Section, Item> view);

/// Builds a row widget for a visible item.
typedef SectionItemBuilder<K extends Object, Section, Item> =
    Widget Function(BuildContext context, ItemView<K, Section, Item> view);

/// A header + items sliver. See the library docs for the two forms.
class SectionedSliverList<K extends Object, Section, Item>
    extends StatelessWidget {
  /// Pull-model declarative form. The widget owns an internal
  /// controller, and the `sections` / `itemsOf` props are
  /// authoritative: every rebuild re-runs the diff against them.
  const SectionedSliverList({
    required Iterable<Section> sections,
    required Iterable<Item> Function(Section section) itemsOf,
    required K Function(Section section) sectionKeyOf,
    required K Function(Item item) itemKeyOf,
    required this.headerBuilder,
    required this.itemBuilder,
    this.collapsible = true,
    this.stickyHeaders = true,
    bool hideEmptySections = false,
    bool initiallyExpanded = true,
    bool? Function(K key, Section section)? initialSectionExpansion,
    bool preserveExpansion = true,
    TreeAnimationStyle animationStyle = const TreeAnimationStyle(),
    double itemIndent = 0.0,
    super.key,
  }) : _controller = null,
       _sections = sections,
       _itemsOf = itemsOf,
       _sectionKeyOf = sectionKeyOf,
       _itemKeyOf = itemKeyOf,
       _hideEmptySections = hideEmptySections,
       _initiallyExpanded = initiallyExpanded,
       _initialSectionExpansion = initialSectionExpansion,
       _preserveExpansion = preserveExpansion,
       _animationStyle = animationStyle,
       _itemIndent = itemIndent;

  /// Push-model imperative form. The caller-owned [controller] is the
  /// authoritative state; the widget only renders it and never diffs.
  ///
  /// Animation, indent and expansion config live on the controller —
  /// there are no props for them here. `collapsible` is advisory: it
  /// sets `SectionView.isCollapsible` but never alters expansion state.
  const SectionedSliverList.controlled({
    required SectionedListController<K, Section, Item> controller,
    required this.headerBuilder,
    required this.itemBuilder,
    this.collapsible = true,
    this.stickyHeaders = true,
    super.key,
  }) : _controller = controller,
       _sections = null,
       _itemsOf = null,
       _sectionKeyOf = null,
       _itemKeyOf = null,
       _hideEmptySections = null,
       _initiallyExpanded = null,
       _initialSectionExpansion = null,
       _preserveExpansion = null,
       _animationStyle = null,
       _itemIndent = null;

  /// Builds the header for each section.
  final SectionHeaderBuilder<K, Section, Item> headerBuilder;

  /// Builds each item row.
  final SectionItemBuilder<K, Section, Item> itemBuilder;

  /// Whether sections can be expanded/collapsed.
  ///
  /// In the declarative form, `false` force-expands every section after
  /// each sync. In `.controlled`, `false` is advisory only — it sets
  /// `SectionView.isCollapsible` but never alters the controller's
  /// expansion state. Either way it lets headers hide their toggle UI.
  final bool collapsible;

  /// Whether section headers stick to the top while their items scroll.
  /// Maps to the underlying `SliverTree.maxStickyDepth`.
  final bool stickyHeaders;

  // Controlled-form storage. Non-null iff this is a `.controlled` widget.
  final SectionedListController<K, Section, Item>? _controller;

  // Declarative-form storage. All non-null iff `_controller` is null.
  final Iterable<Section>? _sections;
  final Iterable<Item> Function(Section section)? _itemsOf;
  final K Function(Section section)? _sectionKeyOf;
  final K Function(Item item)? _itemKeyOf;
  final bool? _hideEmptySections;
  final bool? _initiallyExpanded;
  final bool? Function(K key, Section section)? _initialSectionExpansion;
  final bool? _preserveExpansion;
  final TreeAnimationStyle? _animationStyle;
  final double? _itemIndent;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return _ControlledSectionedSliver<K, Section, Item>(
        controller: controller,
        collapsible: collapsible,
        stickyHeaders: stickyHeaders,
        headerBuilder: headerBuilder,
        itemBuilder: itemBuilder,
      );
    }
    return _DeclarativeSectionedSliver<K, Section, Item>(
      sections: _sections!,
      itemsOf: _itemsOf!,
      sectionKeyOf: _sectionKeyOf!,
      itemKeyOf: _itemKeyOf!,
      collapsible: collapsible,
      stickyHeaders: stickyHeaders,
      hideEmptySections: _hideEmptySections!,
      initiallyExpanded: _initiallyExpanded!,
      initialSectionExpansion: _initialSectionExpansion,
      preserveExpansion: _preserveExpansion!,
      animationStyle: _animationStyle!,
      itemIndent: _itemIndent!,
      headerBuilder: headerBuilder,
      itemBuilder: itemBuilder,
    );
  }
}

/// Declarative impl: owns a [SectionedListController], diffs the
/// `sections` / `itemsOf` props into it on every rebuild, then delegates
/// rendering to [_ControlledSectionedSliver].
class _DeclarativeSectionedSliver<K extends Object, Section, Item>
    extends StatefulWidget {
  const _DeclarativeSectionedSliver({
    required this.sections,
    required this.itemsOf,
    required this.sectionKeyOf,
    required this.itemKeyOf,
    required this.collapsible,
    required this.stickyHeaders,
    required this.hideEmptySections,
    required this.initiallyExpanded,
    required this.initialSectionExpansion,
    required this.preserveExpansion,
    required this.animationStyle,
    required this.itemIndent,
    required this.headerBuilder,
    required this.itemBuilder,
  });

  final Iterable<Section> sections;
  final Iterable<Item> Function(Section section) itemsOf;
  final K Function(Section section) sectionKeyOf;
  final K Function(Item item) itemKeyOf;
  final bool collapsible;
  final bool stickyHeaders;
  final bool hideEmptySections;
  final bool initiallyExpanded;
  final bool? Function(K key, Section section)? initialSectionExpansion;
  final bool preserveExpansion;
  final TreeAnimationStyle animationStyle;
  final double itemIndent;
  final SectionHeaderBuilder<K, Section, Item> headerBuilder;
  final SectionItemBuilder<K, Section, Item> itemBuilder;

  @override
  State<_DeclarativeSectionedSliver<K, Section, Item>> createState() {
    return _DeclarativeSectionedSliverState<K, Section, Item>();
  }
}

class _DeclarativeSectionedSliverState<K extends Object, Section, Item>
    extends State<_DeclarativeSectionedSliver<K, Section, Item>>
    with TickerProviderStateMixin {
  late final SectionedListController<K, Section, Item> _controller;
  bool _hasSyncedOnce = false;

  @override
  void initState() {
    super.initState();
    _controller = SectionedListController<K, Section, Item>(
      vsync: this,
      sectionKeyOf: widget.sectionKeyOf,
      itemKeyOf: widget.itemKeyOf,
      animationStyle: widget.animationStyle,
      itemIndent: widget.itemIndent,
      preserveExpansion: widget.preserveExpansion,
    );
    _sync(animate: false);
    _hasSyncedOnce = true;
  }

  @override
  void didUpdateWidget(_DeclarativeSectionedSliver<K, Section, Item> oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Propagate animation / indent / preserveExpansion params.
    if (oldWidget.animationStyle != widget.animationStyle) {
      _controller.animationStyle = widget.animationStyle;
    }
    if (oldWidget.itemIndent != widget.itemIndent) {
      _controller.itemIndent = widget.itemIndent;
    }
    if (oldWidget.preserveExpansion != widget.preserveExpansion) {
      _controller.preserveExpansion = widget.preserveExpansion;
    }

    _sync(animate: true);
  }

  void _sync({required bool animate}) {
    final sections = widget.sections;
    final itemsOf = widget.itemsOf;
    final filteredSections = widget.hideEmptySections
        ? <Section>[
            for (final s in sections)
              if (itemsOf(s).isNotEmpty) s,
          ]
        : sections;
    _runSync(filteredSections, itemsOf, animate: animate);
  }

  void _runSync(
    Iterable<Section> sections,
    Iterable<Item> Function(Section) itemsOf, {
    required bool animate,
  }) {
    final keyOf = widget.sectionKeyOf;
    // Snapshot which sections existed before the sync. On first sync
    // the internal controller is always empty (created in initState and
    // not mutated until here), so `knownSections` is `{}` and
    // `initiallyExpanded` / `initialSectionExpansion` applies to every
    // section. On subsequent syncs, only sections genuinely new in this
    // sync (absent from the pre-sync snapshot) get the initial-expansion
    // treatment — existing sections keep whatever expansion state the
    // user has set since.
    final knownSections = _hasSyncedOnce
        ? _controller.sectionKeys().toSet()
        : <K>{};

    final desiredList = sections.toList(growable: false);
    _controller.setSections(
      desiredList,
      itemsOf: itemsOf,
      animate: animate,
    );

    if (widget.collapsible) {
      _applyInitialExpansion(
        knownSections,
        desiredList,
        keyOf,
        animate: animate,
      );
    } else {
      // Non-collapsible: keep everything expanded regardless of the
      // initial-expansion config.
      _controller.expandAll(animate: animate);
    }
  }

  void _applyInitialExpansion(
    Set<K> knownSections,
    List<Section> desired,
    K Function(Section) keyOf, {
    required bool animate,
  }) {
    _controller.runBatch(() {
      for (final section in desired) {
        final k = keyOf(section);
        if (knownSections.contains(k)) {
          continue;
        }
        if (!_controller.hasSection(k)) {
          continue;
        }
        final shouldExpand = _resolveInitialExpansion(k, section);
        if (shouldExpand && !_controller.isExpanded(k)) {
          _controller.expandSection(k, animate: animate);
        } else if (!shouldExpand && _controller.isExpanded(k)) {
          _controller.collapseSection(k, animate: animate);
        }
      }
    });
  }

  bool _resolveInitialExpansion(K key, Section section) {
    final override = widget.initialSectionExpansion?.call(key, section);
    if (override != null) {
      return override;
    }
    return widget.initiallyExpanded;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Once the props are diffed into the controller, rendering is
    // identical to the controlled form — delegate to it.
    return _ControlledSectionedSliver<K, Section, Item>(
      controller: _controller,
      collapsible: widget.collapsible,
      stickyHeaders: widget.stickyHeaders,
      headerBuilder: widget.headerBuilder,
      itemBuilder: widget.itemBuilder,
    );
  }
}

/// Controlled impl, and the shared renderer for both forms: turns a
/// [SectionedListController] into a [SliverTree], mapping section/item
/// nodes to [SectionView] / [ItemView] for the builders.
class _ControlledSectionedSliver<K extends Object, Section, Item>
    extends StatelessWidget {
  const _ControlledSectionedSliver({
    required this.controller,
    required this.collapsible,
    required this.stickyHeaders,
    required this.headerBuilder,
    required this.itemBuilder,
  });

  final SectionedListController<K, Section, Item> controller;
  final bool collapsible;
  final bool stickyHeaders;
  final SectionHeaderBuilder<K, Section, Item> headerBuilder;
  final SectionItemBuilder<K, Section, Item> itemBuilder;

  @override
  Widget build(BuildContext context) {
    final treeController = controller.treeController;
    // Key on controller identity so a controller swap (in `.controlled`
    // usage) tears down the old SliverTree element and its per-key child
    // caches rather than rewiring them in place.
    return SliverTree<SecKey<K>, SecPayload<Section, Item>>(
      key: ObjectKey(treeController),
      controller: treeController,
      maxStickyDepth: stickyHeaders ? 1 : 0,
      nodeBuilder: (ctx, key, depth) {
        final node = treeController.getNodeData(key);
        if (node == null) {
          return const SizedBox.shrink();
        }
        return switch (node.data) {
          SectionPayload<Section, Item>(value: final section) => headerBuilder(
            ctx,
            SectionView<K, Section, Item>(
              key: (key as SectionKey<K>).value,
              section: section,
              itemCount: treeController.getChildCount(key),
              isExpanded: treeController.isExpanded(key),
              isCollapsible: collapsible,
              controller: controller,
            ),
          ),
          ItemPayload<Section, Item>(value: final item) => _buildItem(
            ctx,
            key as ItemKey<K>,
            item,
          ),
        };
      },
    );
  }

  Widget _buildItem(BuildContext ctx, ItemKey<K> key, Item item) {
    final treeController = controller.treeController;
    final parent = treeController.getParent(key);
    if (parent is! SectionKey<K>) {
      return const SizedBox.shrink();
    }
    final sectionPayload = treeController.getNodeData(parent);
    if (sectionPayload == null ||
        sectionPayload.data is! SectionPayload<Section, Item>) {
      return const SizedBox.shrink();
    }
    final section =
        (sectionPayload.data as SectionPayload<Section, Item>).value;
    final indexInSection = treeController.getIndexInParent(key);
    return itemBuilder(
      ctx,
      ItemView<K, Section, Item>(
        key: key.value,
        item: item,
        sectionKey: parent.value,
        section: section,
        indexInSection: indexInSection,
        controller: controller,
      ),
    );
  }
}
