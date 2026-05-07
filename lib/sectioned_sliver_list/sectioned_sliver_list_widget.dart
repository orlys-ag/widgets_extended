/// Header + items convenience sliver, built on top of [SliverTree].
///
/// Models a strict 2-level structure (sections containing items, items
/// have no children) with separate types and builders for each level,
/// animated insert/remove/reparent, sticky headers, and an optional
/// external controller.
///
/// Type parameters: `<K extends Object, Section, Item>`. Section and
/// item key domains share a single user-facing parameter `K` and are
/// kept disjoint internally via the wrapper types in `_internal_keys.dart`.
///
/// Three constructors with non-overlapping responsibilities:
///
/// - default — pull-model declarative form. Widget owns an internal
///   controller. The prop is authoritative on every rebuild:
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
/// - `.fromMap` — `Map<Section, List<Item>>` form. Map iteration order
///   is render order:
///   ```dart
///   SectionedSliverList.fromMap(
///     sections: files.groupListsBy((f) => f.folder),
///     sectionKeyOf: (folder) => folder.id,
///     itemKeyOf: (file) => file.id,
///     headerBuilder: ..., itemBuilder: ...,
///   )
///   ```
///
/// - `.controlled` — external-controller form. The controller IS the
///   source of truth. No `sections`/`itemsOf` props, no expansion config,
///   no animation params, no `itemIndent` — set those on the controller.
///   Use this when imperative drift must survive parent rebuilds:
///   ```dart
///   SectionedSliverList.controlled(
///     controller: myController,
///     headerBuilder: ..., itemBuilder: ...,
///   )
///   ```
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

/// Internal mode discriminator. The mode is fixed at construction time;
/// `didUpdateWidget` asserts that it does not change across rebuilds.
enum _Mode { iterable, map, controlled }

class SectionedSliverList<K extends Object, Section, Item>
    extends StatefulWidget {
  /// Pull-model declarative form. Widget owns an internal controller.
  /// The `sections` / `itemsOf` props are authoritative on every
  /// rebuild — imperative drift between rebuilds (`controller.addItem`
  /// via [SectionedSliverListState.controller]) survives until the next
  /// rebuild that changes the prop, at which point the diff re-runs.
  const SectionedSliverList({
    required Iterable<Section> sections,
    required Iterable<Item> Function(Section section) itemsOf,
    required K Function(Section section) sectionKeyOf,
    required K Function(Item item) itemKeyOf,
    required this.headerBuilder,
    required this.itemBuilder,
    this.collapsible = true,
    this.stickyHeaders = true,
    this.hideEmptySections = false,
    this.initiallyExpanded = true,
    this.initialSectionExpansion,
    this.preserveExpansion = true,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.itemIndent = 0.0,
    super.key,
  }) : _mode = _Mode.iterable,
       _sections = sections,
       _itemsOf = itemsOf,
       _sectionKeyOf = sectionKeyOf,
       _itemKeyOf = itemKeyOf,
       _mapSections = null,
       _externalController = null;

  /// `Map<Section, List<Item>>` form. Map iteration order = render
  /// order. Two map entries with the same `sectionKeyOf` result assert
  /// in debug; release falls back to last-iterated payload.
  const SectionedSliverList.fromMap({
    required Map<Section, List<Item>> sections,
    required K Function(Section section) sectionKeyOf,
    required K Function(Item item) itemKeyOf,
    required this.headerBuilder,
    required this.itemBuilder,
    this.collapsible = true,
    this.stickyHeaders = true,
    this.hideEmptySections = false,
    this.initiallyExpanded = true,
    this.initialSectionExpansion,
    this.preserveExpansion = true,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.itemIndent = 0.0,
    super.key,
  }) : _mode = _Mode.map,
       _sections = null,
       _itemsOf = null,
       _sectionKeyOf = sectionKeyOf,
       _itemKeyOf = itemKeyOf,
       _mapSections = sections,
       _externalController = null;

  /// External-controller form. The controller IS the source of truth.
  /// No `sections`/`itemsOf` props, no expansion config, no animation
  /// params, no `itemIndent` — set them on the controller.
  ///
  /// Use this when imperative drift must survive parent rebuilds, or
  /// when an outer state-management layer owns the section/item state
  /// directly.
  const SectionedSliverList.controlled({
    required SectionedListController<K, Section, Item> controller,
    required this.headerBuilder,
    required this.itemBuilder,
    this.collapsible = true,
    this.stickyHeaders = true,
    super.key,
  }) : _mode = _Mode.controlled,
       _sections = null,
       _itemsOf = null,
       _sectionKeyOf = null,
       _itemKeyOf = null,
       _mapSections = null,
       _externalController = controller,
       hideEmptySections = false,
       initiallyExpanded = true,
       initialSectionExpansion = null,
       preserveExpansion = true,
       animationDuration = const Duration(milliseconds: 300),
       animationCurve = Curves.easeInOut,
       itemIndent = 0.0;

  // ──────────────────────────────────────────────────────────────────
  // Mode-private storage. Each named constructor sets _mode and the
  // matching fields; the others are null. The State dispatches on
  // _mode and reads only the fields that mode populates.
  // ──────────────────────────────────────────────────────────────────

  final _Mode _mode;
  final Iterable<Section>? _sections;
  final Iterable<Item> Function(Section section)? _itemsOf;
  final Map<Section, List<Item>>? _mapSections;
  final K Function(Section section)? _sectionKeyOf;
  final K Function(Item item)? _itemKeyOf;
  final SectionedListController<K, Section, Item>? _externalController;

  // ──────────────────────────────────────────────────────────────────
  // Public fields (shared across modes — but with mode-specific
  // semantics for some, see docstrings).
  // ──────────────────────────────────────────────────────────────────

  /// Builds the header for each section.
  final SectionHeaderBuilder<K, Section, Item> headerBuilder;

  /// Builds each item row.
  final SectionItemBuilder<K, Section, Item> itemBuilder;

  /// Whether sections can be expanded/collapsed.
  ///
  /// In `default`/`.fromMap` modes, `false` force-expands all sections
  /// after every sync. In `.controlled` mode, `false` is purely advisory:
  /// it sets `SectionView.isCollapsible` to `false` so headers can hide
  /// their toggle UI; the controller's expansion state remains
  /// authoritative.
  final bool collapsible;

  /// Whether section headers stick to the top while their items scroll.
  /// Maps to the underlying `SliverTree.maxStickyDepth`.
  final bool stickyHeaders;

  /// When true, sections with zero items are filtered out of the
  /// declarative input before the diff runs. Default/`.fromMap` only.
  final bool hideEmptySections;

  /// Default initial-expansion state for newly synced sections, used
  /// when [initialSectionExpansion] is null or returns null for the
  /// section. Default/`.fromMap` only.
  final bool initiallyExpanded;

  /// Per-section initial expansion override. Default/`.fromMap` only.
  final bool? Function(K key, Section section)? initialSectionExpansion;

  /// When true, the underlying tree remembers expansion state across
  /// remove/re-add cycles. Default/`.fromMap` only — set on the
  /// controller in `.controlled` mode.
  final bool preserveExpansion;

  /// Animation duration for expand/collapse and add/remove.
  /// Default/`.fromMap` only — set on the controller in `.controlled`.
  final Duration animationDuration;

  /// Animation curve. Default/`.fromMap` only — set on the controller
  /// in `.controlled`.
  final Curve animationCurve;

  /// Visual indent for items under headers, in logical pixels.
  /// Default/`.fromMap` only — set on the controller in `.controlled`.
  final double itemIndent;

  @override
  State<SectionedSliverList<K, Section, Item>> createState() {
    return SectionedSliverListState<K, Section, Item>();
  }
}

class SectionedSliverListState<K extends Object, Section, Item>
    extends State<SectionedSliverList<K, Section, Item>>
    with TickerProviderStateMixin {
  SectionedListController<K, Section, Item>? _internalController;
  late SectionedListController<K, Section, Item> _activeController;
  bool _hasSyncedOnce = false;

  /// The active controller — internal for default/`fromMap`, external
  /// for `.controlled`. Stable for the widget's lifetime unless the
  /// `controller:` argument to `.controlled` is reassigned across
  /// rebuilds.
  SectionedListController<K, Section, Item> get controller {
    return _activeController;
  }

  @override
  void initState() {
    super.initState();
    _adoptController();
    _sync(animate: false);
    _hasSyncedOnce = true;
  }

  @override
  void didUpdateWidget(SectionedSliverList<K, Section, Item> oldWidget) {
    super.didUpdateWidget(oldWidget);

    assert(
      oldWidget._mode == widget._mode,
      "SectionedSliverList: mode transition across rebuild is not "
      "supported (was ${oldWidget._mode}, now ${widget._mode}). To "
      "switch between default/.fromMap/.controlled, change the widget's "
      "Key so Flutter tears down the old Element and mounts a new one.",
    );

    final externalSwap =
        oldWidget._externalController != widget._externalController;
    if (externalSwap) {
      _activeController.debugUnbindWidget();
      if (_internalController != null) {
        _internalController!.dispose();
        _internalController = null;
      }
      _adoptController();
      // Treat as a fresh mount against the new controller — reset the
      // first-sync flag so initial-expansion config (in iterable/map
      // modes) re-applies against the new controller's state.
      _hasSyncedOnce = false;
      _sync(animate: true);
      _hasSyncedOnce = true;
      return;
    }

    if (widget._mode != _Mode.controlled) {
      // Internally owned: propagate animation/indent/preserveExpansion
      // params on rebuild.
      if (oldWidget.animationDuration != widget.animationDuration) {
        _activeController.animationDuration = widget.animationDuration;
      }
      if (oldWidget.animationCurve != widget.animationCurve) {
        _activeController.animationCurve = widget.animationCurve;
      }
      if (oldWidget.itemIndent != widget.itemIndent) {
        _activeController.itemIndent = widget.itemIndent;
      }
      if (oldWidget.preserveExpansion != widget.preserveExpansion) {
        _activeController.preserveExpansion = widget.preserveExpansion;
      }
    }

    _sync(animate: true);
  }

  void _adoptController() {
    switch (widget._mode) {
      case _Mode.iterable:
      case _Mode.map:
        _internalController = SectionedListController<K, Section, Item>(
          vsync: this,
          sectionKeyOf: widget._sectionKeyOf!,
          itemKeyOf: widget._itemKeyOf!,
          animationDuration: widget.animationDuration,
          animationCurve: widget.animationCurve,
          itemIndent: widget.itemIndent,
          preserveExpansion: widget.preserveExpansion,
        );
        _activeController = _internalController!;
      case _Mode.controlled:
        _activeController = widget._externalController!;
    }
    _activeController.debugBindWidget();
  }

  void _sync({required bool animate}) {
    switch (widget._mode) {
      case _Mode.iterable:
        _syncIterable(animate: animate);
      case _Mode.map:
        _syncMap(animate: animate);
      case _Mode.controlled:
        // Controller is authoritative — no prop to diff against.
        break;
    }
  }

  void _syncIterable({required bool animate}) {
    final sections = widget._sections!;
    final itemsOf = widget._itemsOf!;
    final filteredSections = widget.hideEmptySections
        ? <Section>[
            for (final s in sections)
              if (itemsOf(s).isNotEmpty) s,
          ]
        : sections;
    _runSync(filteredSections, itemsOf, animate: animate);
  }

  void _syncMap({required bool animate}) {
    final mapSections = widget._mapSections!;
    final keyOf = widget._sectionKeyOf!;
    // Detect duplicate section keys (two map entries that map to the
    // same sectionKeyOf result). Asserts in debug; release falls back
    // to the last-iterated payload by overwriting earlier hits.
    assert(() {
      final seen = <K>{};
      for (final entry in mapSections.entries) {
        final k = keyOf(entry.key);
        if (!seen.add(k)) {
          throw FlutterError(
            "SectionedSliverList.fromMap: two map entries produced the "
            "same section key '$k'. Section payload equality must be "
            "aligned with sectionKeyOf (use Equatable, freezed, or "
            "override ==/hashCode), or use the default constructor with "
            "explicit (Section, items) shape.",
          );
        }
      }
      return true;
    }());

    final dedup = <K, Section>{};
    for (final entry in mapSections.entries) {
      dedup[keyOf(entry.key)] = entry.key;
    }
    final orderedSections = <Section>[];
    final itemsBySection = <K, List<Item>>{};
    for (final entry in mapSections.entries) {
      final k = keyOf(entry.key);
      if (dedup[k] != entry.key) {
        // Earlier duplicate; release-mode skips so the last wins.
        continue;
      }
      orderedSections.add(entry.key);
      itemsBySection[k] = entry.value;
    }
    final filtered = widget.hideEmptySections
        ? <Section>[
            for (final s in orderedSections)
              if ((itemsBySection[keyOf(s)] ?? const []).isNotEmpty) s,
          ]
        : orderedSections;
    Iterable<Item> resolveItems(Section s) {
      return itemsBySection[keyOf(s)] ?? const [];
    }

    _runSync(filtered, resolveItems, animate: animate);
  }

  void _runSync(
    Iterable<Section> sections,
    Iterable<Item> Function(Section) itemsOf, {
    required bool animate,
  }) {
    final keyOf = widget._sectionKeyOf!;
    // Snapshot which sections existed before the sync. On first sync
    // the internally-owned controller is always empty (created in
    // _adoptController and not mutated until here), so `knownSections`
    // is `{}` and `initiallyExpanded` / `initialSectionExpansion`
    // applies to every section. On subsequent syncs, only sections
    // genuinely new in this sync (absent from the pre-sync snapshot)
    // get the initial-expansion treatment — existing sections keep
    // whatever expansion state the user has set since.
    final knownSections = _hasSyncedOnce
        ? _activeController.sectionKeys.toSet()
        : <K>{};

    final desiredList = sections.toList(growable: false);
    _activeController.setSections(
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
      _activeController.expandAll(animate: animate);
    }
  }

  void _applyInitialExpansion(
    Set<K> knownSections,
    List<Section> desired,
    K Function(Section) keyOf, {
    required bool animate,
  }) {
    _activeController.runBatch(() {
      for (final section in desired) {
        final k = keyOf(section);
        if (knownSections.contains(k)) {
          continue;
        }
        if (!_activeController.hasSection(k)) {
          continue;
        }
        final shouldExpand = _resolveInitialExpansion(k, section);
        if (shouldExpand && !_activeController.isExpanded(k)) {
          _activeController.expandSection(k, animate: animate);
        } else if (!shouldExpand && _activeController.isExpanded(k)) {
          _activeController.collapseSection(k, animate: animate);
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
    _activeController.debugUnbindWidget();
    if (_internalController != null) {
      _internalController!.dispose();
      _internalController = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final treeController = _activeController.treeController;
    // The SliverTree element wires up controller listeners and per-key
    // child caches; swapping controllers in place is fragile, so we
    // give it a key tied to the controller identity. When the user
    // swaps the external controller across rebuilds, this key changes,
    // which forces Flutter to tear down the old SliverTree element and
    // build a fresh one against the new controller.
    return SliverTree<SecKey<K>, SecPayload<Section, Item>>(
      key: ObjectKey(treeController),
      controller: treeController,
      maxStickyDepth: widget.stickyHeaders ? 1 : 0,
      nodeBuilder: (ctx, key, depth) {
        final node = treeController.getNodeData(key);
        if (node == null) {
          return const SizedBox.shrink();
        }
        return switch (node.data) {
          SectionPayload<Section, Item>(value: final section) =>
            widget.headerBuilder(
              ctx,
              SectionView<K, Section, Item>(
                key: (key as SectionKey<K>).value,
                section: section,
                itemCount: treeController.getChildCount(key),
                isExpanded: treeController.isExpanded(key),
                isCollapsible: widget.collapsible,
                controller: _activeController,
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
    final treeController = _activeController.treeController;
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
    return widget.itemBuilder(
      ctx,
      ItemView<K, Section, Item>(
        key: key.value,
        item: item,
        sectionKey: parent.value,
        section: section,
        indexInSection: indexInSection,
        controller: _activeController,
      ),
    );
  }
}
