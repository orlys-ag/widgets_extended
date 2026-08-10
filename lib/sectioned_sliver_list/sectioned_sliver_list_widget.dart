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

import '../sliver_tree/_deferred_sync_gate.dart';
import '../sliver_tree/sliver_tree.dart';
import '_internal_keys.dart';
import '_reorder_bridge.dart';
import 'sectioned_list_controller.dart';
import 'sectioned_reorder_config.dart';
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
  /// authoritative.
  ///
  /// ## Rebuild convention
  ///
  /// Rebuilds re-diff only when `sections` is a different instance than
  /// the previous build's. An ancestor that rebuilds every frame while
  /// passing the same collection would otherwise pay an O(all items) walk
  /// each time for nothing. This is the same convention as
  /// [ListView.children], and the same one [SyncedSliverTree] uses:
  /// mutating a collection in place is not observed; pass a new instance
  /// to signal a change.
  ///
  /// `itemsOf` is deliberately NOT part of that check, because an inline
  /// lambda is a fresh instance on every build and would defeat it
  /// entirely. It must be a pure function of its argument. When a
  /// section's ITEMS change without the section list changing, pass a new
  /// `sections` instance (`[...sections]` is enough) to signal it.
  ///
  /// `collapsible`, `hideEmptySections` and `preserveExpansion` are
  /// checked separately and each force a re-diff on their own, since they
  /// change what a sync produces from unchanged input.
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
    this.reorder,
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
    this.reorder,
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

  /// Enables drag-and-drop reorder. Null disables it at zero cost.
  ///
  /// Items reorder by default and sections do not. In this declarative
  /// form a kind is enabled only when its flag is set AND its callback
  /// exists, because here the `sections` / `itemsOf` props are
  /// authoritative and a drop nothing records is undone by the next diff.
  final SectionedReorderConfig<K, Section, Item>? reorder;

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
      // `.controlled` is the ONLY form without a TickerProvider of its
      // own, so it is the only one that needs a State object to host the
      // reorder controller. Every other caller keeps the stateless path.
      if (reorder != null) {
        return _ControlledReorderableSectionedSliver<K, Section, Item>(
          controller: controller,
          collapsible: collapsible,
          stickyHeaders: stickyHeaders,
          headerBuilder: headerBuilder,
          itemBuilder: itemBuilder,
          reorder: reorder!,
        );
      }
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
      reorder: reorder,
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
    required this.reorder,
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
  final SectionedReorderConfig<K, Section, Item>? reorder;

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

  /// Non-null iff reorder was enabled at construction. The renderer
  /// dispatches on THIS rather than on `widget.reorder`, so a release
  /// build that flips the config's null-ness degrades to "reorder stays
  /// off" instead of reaching a bridge that was never built.
  SectionedReorderBridge<K, Section, Item>? _bridge;

  /// Holds a structural diff while a drag is live. Built iff [_bridge]
  /// is (reorder cannot be added or removed after construction; see the
  /// assert in [didUpdateWidget]), so every use is null-guarded the same
  /// way [_bridge]'s are.
  DeferredSyncGate<SecKey<K>>? _syncGate;

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
    final initial = widget.reorder;
    if (initial != null) {
      _bridge = SectionedReorderBridge<K, Section, Item>(
        controller: _controller,
        // Read through a closure so the config's CONTENTS stay live
        // across rebuilds even though the tree controller captures these
        // forwarders once.
        // Falls back to the config captured at construction, so a
        // release-mode flip to null degrades rather than throwing from
        // inside a gesture callback. `reorder`'s presence is asserted to
        // be construction-time in debug.
        configOf: () {
          return widget.reorder ?? initial;
        },
        // Declarative: the props are authoritative, so a kind without its
        // callback must not start rather than commit-and-vanish.
        requireCallbacks: true,
        vsync: this,
      );
      _syncGate = DeferredSyncGate<SecKey<K>>(
        reorderController: _bridge!.reorderController,
        isMounted: () {
          return mounted;
        },
        onSync: () {
          _sync(animate: true);
        },
      );
      // BEFORE the first sync, unlike `SyncedSliverTree` (which attaches
      // after its initial expansion pass). Each owner keeps its position.
      _syncGate!.attach();
    }
    _sync(animate: false);
    _hasSyncedOnce = true;
  }

  @override
  void didUpdateWidget(
    _DeclarativeSectionedSliver<K, Section, Item> oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    assert(
      (oldWidget.reorder == null) == (widget.reorder == null),
      "SectionedSliverList.reorder cannot be added or removed after the "
      "widget is created: it changes the widget type at this slot and "
      "would orphan a live drag. Keep the config and return false from "
      "canDragItem / canDragSection to disable reordering at runtime.",
    );

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
    // Drag tunings are live like the rest of the config's contents; each
    // value is captured per drag session, so a change applies from the
    // next drag.
    _bridge?.updateDragTunings();

    // ONE decision point, mirroring `SyncedSliverTree.didUpdateWidget`.
    // `needsSync` folds together every reason a diff is owed so the drag
    // deferral below reads as a single rule rather than one restated per
    // reason.
    var needsSync = _syncGate?.isDeferred ?? false;

    // Props that change what a sync PRODUCES from unchanged `sections`.
    // `collapsible` decides whether the sync force-expands everything and
    // `hideEmptySections` decides which sections survive the filter, so
    // either flipping owes a diff even when the collection is identical.
    // `preserveExpansion` rebuilds the controller's sync layer.
    if (oldWidget.collapsible != widget.collapsible ||
        oldWidget.hideEmptySections != widget.hideEmptySections ||
        oldWidget.preserveExpansion != widget.preserveExpansion) {
      needsSync = true;
    } else if (!identical(oldWidget.sections, widget.sections)) {
      // Identity fast path: callers routinely rebuild an ancestor every
      // frame while passing the SAME collection instance, and re-running
      // the diff is O(all items) UI-thread work for zero change. Standard
      // Flutter convention (same as ListView.children): mutating a
      // collection in place requires a new instance to be observed.
      //
      // `itemsOf` is deliberately NOT part of this check. It is
      // near-universally an inline lambda, so a fresh closure instance
      // every build would make the gate miss every time, which is exactly
      // the re-diff it exists to prevent. It must instead be a pure
      // function of its argument, with a new `sections` instance
      // signalling that anything it returns has changed. Documented on
      // the constructor.
      //
      // `initiallyExpanded` and `initialSectionExpansion` are excluded for
      // a different reason: they apply only to sections that are NEW in a
      // sync, so with an identical collection there is nothing for a
      // changed value to apply to.
      needsSync = true;
    }

    if (!needsSync) {
      return;
    }
    if (_syncGate?.isDragging ?? false) {
      // A diff underneath a live drag inserts and removes siblings around
      // the drop target, invalidates the pinned row, and fights the
      // make-room preview. Covers `collapsible: false` too, whose sync
      // path calls `expandAll` on every run.
      _syncGate?.markDeferred();
      return;
    }
    _sync(animate: true);
    _syncGate?.markSynced();
  }

  void _sync({required bool animate}) {
    final itemsOf = widget.itemsOf;
    if (!widget.hideEmptySections) {
      _runSync(widget.sections, itemsOf, animate: animate);
      return;
    }
    // Materialize ONCE. The emptiness filter and the diff both need every
    // section's items, and `itemsOf` is a caller callback documented as
    // accepting any Iterable, so it is routinely a where/map chain that
    // costs real work per evaluation. Asking twice ran that chain twice
    // per section per sync purely to learn `isNotEmpty` and then throw the
    // answer away.
    final keyOf = widget.sectionKeyOf;
    final kept = <Section>[];
    final itemsByKey = <K, List<Item>>{};
    for (final section in widget.sections) {
      final items = itemsOf(section).toList(growable: false);
      if (items.isEmpty) {
        continue;
      }
      kept.add(section);
      itemsByKey[keyOf(section)] = items;
    }
    _runSync(
      kept,
      (section) {
        return itemsByKey[keyOf(section)] ?? const [];
      },
      animate: animate,
    );
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
    _controller.setSections(desiredList, itemsOf: itemsOf, animate: animate);

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
    // BEFORE the sectioned controller, which disposes the underlying
    // tree controller: tearing down a live session reaches back into it.
    _syncGate?.dispose();
    _bridge?.dispose();
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
      bridge: _bridge,
    );
  }
}

/// `.controlled` plus reorder: the one form with no [TickerProvider] of
/// its own, so the only one that needs a State object purely to host the
/// reorder controller. Everything else delegates straight through.
class _ControlledReorderableSectionedSliver<K extends Object, Section, Item>
    extends StatefulWidget {
  const _ControlledReorderableSectionedSliver({
    required this.controller,
    required this.collapsible,
    required this.stickyHeaders,
    required this.headerBuilder,
    required this.itemBuilder,
    required this.reorder,
  });

  final SectionedListController<K, Section, Item> controller;
  final bool collapsible;
  final bool stickyHeaders;
  final SectionHeaderBuilder<K, Section, Item> headerBuilder;
  final SectionItemBuilder<K, Section, Item> itemBuilder;
  final SectionedReorderConfig<K, Section, Item> reorder;

  @override
  State<_ControlledReorderableSectionedSliver<K, Section, Item>> createState() {
    return _ControlledReorderableSectionedSliverState<K, Section, Item>();
  }
}

class _ControlledReorderableSectionedSliverState<
  K extends Object,
  Section,
  Item
>
    extends State<_ControlledReorderableSectionedSliver<K, Section, Item>>
    with TickerProviderStateMixin {
  late SectionedReorderBridge<K, Section, Item> _bridge;

  @override
  void initState() {
    super.initState();
    _bridge = _createBridge();
  }

  SectionedReorderBridge<K, Section, Item> _createBridge() {
    return SectionedReorderBridge<K, Section, Item>(
      controller: widget.controller,
      configOf: () {
        return widget.reorder;
      },
      // Controlled: the caller's controller IS the truth and nothing
      // re-diffs, so a committed drop simply sticks. The callbacks are
      // informational and a kind stays enabled without one.
      requireCallbacks: false,
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(
    _ControlledReorderableSectionedSliver<K, Section, Item> oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      // The renderer keys its sliver on controller identity, so the whole
      // subtree is replaced; the bridge must follow or it would commit
      // drops against the previous controller.
      _bridge.dispose();
      _bridge = _createBridge();
    }
    // Drag tunings are live; captured per drag session, so a change
    // applies from the next drag. Idempotent after a bridge recreation,
    // whose constructor already seeded the same values.
    _bridge.updateDragTunings();
  }

  @override
  void dispose() {
    // The caller owns the sectioned controller, so only the bridge is
    // ours to tear down.
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ControlledSectionedSliver<K, Section, Item>(
      controller: widget.controller,
      collapsible: widget.collapsible,
      stickyHeaders: widget.stickyHeaders,
      headerBuilder: widget.headerBuilder,
      itemBuilder: widget.itemBuilder,
      bridge: _bridge,
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
    this.bridge,
  });

  final SectionedListController<K, Section, Item> controller;
  final bool collapsible;
  final bool stickyHeaders;
  final SectionHeaderBuilder<K, Section, Item> headerBuilder;
  final SectionItemBuilder<K, Section, Item> itemBuilder;

  /// Supplied by whichever owner has a [TickerProvider]. Taken as a
  /// PARAMETER so this renderer stays a `StatelessWidget` for every
  /// caller that is not reordering, which is the common case.
  final SectionedReorderBridge<K, Section, Item>? bridge;

  /// Presentation config, read THROUGH the bridge rather than passed
  /// beside it. Two nullable fields that had to agree were one rebuild
  /// away from disagreeing, and the order that disagreed threw.
  SectionedReorderConfig<K, Section, Item>? get reorder {
    return bridge?.config;
  }

  @override
  Widget build(BuildContext context) {
    final treeController = controller.treeController;
    // Key on controller identity so a controller swap (in `.controlled`
    // usage) tears down the old sliver element and its per-key child
    // caches rather than rewiring them in place. Load-bearing for reorder
    // too: without it a swap mid-drag preserves the reorderable widget's
    // State, stranding its overlay proxy and its hidden source row.
    final swapKey = ObjectKey(treeController);
    final bridge = this.bridge;

    if (bridge == null) {
      return SliverTree<SecKey<K>, SecPayload<Section, Item>>(
        key: swapKey,
        controller: treeController,
        maxStickyDepth: stickyHeaders ? 1 : 0,
        nodeBuilder: (ctx, key, depth) {
          return _dispatch(ctx, key);
        },
      );
    }

    final config = reorder!;
    return SliverReorderableTree<SecKey<K>, SecPayload<Section, Item>>(
      key: swapKey,
      controller: treeController,
      reorderController: bridge.reorderController,
      maxStickyDepth: stickyHeaders ? 1 : 0,
      // The indent this module actually renders. The shape policy leaves
      // exactly one legal depth per drag kind at every boundary, so the
      // hint cannot change the outcome, but keying it on a column that is
      // never drawn would still be wrong.
      indentWidth: controller.itemIndent,
      showDragProxy: config.showDragProxy,
      hapticsOnDrag: config.hapticsOnDrag,
      // A stable tear-off: rows cache this through an inherited scope, so
      // a fresh closure per build would rebuild every visible row on
      // every ancestor rebuild.
      semanticsActionsBuilder: bridge.semanticsActionsBuilder,
      dragProxyBuilder:
          config.itemDragProxyBuilder == null &&
              config.sectionDragProxyBuilder == null
          ? null
          : _buildDragProxy,
      nodeBuilder: (ctx, key, depth) {
        return _dispatch(ctx, key);
      },
    );
  }

  /// Pure dispatch. The two bail-outs below return a zero-extent
  /// placeholder and are deliberately left BARE: a drag handle on nothing
  /// is worse than no handle.
  Widget _dispatch(BuildContext ctx, SecKey<K> key) {
    final node = controller.treeController.getNodeData(key);
    if (node == null) {
      return const SizedBox.shrink();
    }
    // The default handle is gated PER KIND, so a kind that is switched
    // off never gets a gesture even though its rows are still wrapped by
    // the tree layer (which is what keeps them drop TARGETS and keeps
    // their semantics coherent).
    //
    // The enablement question is NOT the same as `canDragItem`'s. That
    // one refuses individual rows within a live kind and merely DISARMS
    // their handles; this one says the kind can never drag at all, so
    // there is no reason to install one.
    //
    // Reachable by omission, not just by setting a flag: the declarative
    // form enables a kind only when its flag is set AND its callback
    // exists, and `reorderItems` defaults to true.
    final bridge = this.bridge;
    return switch (node.data) {
      SectionPayload<Section, Item>(value: final section) => _withDefaultHandle(
        headerBuilder(ctx, _sectionView(key as SectionKey<K>, section)),
        enabled:
            bridge != null &&
            bridge.sectionsEnabled() &&
            (reorder?.buildDefaultSectionDragHandles ?? false),
      ),
      ItemPayload<Section, Item>(value: final item) => _buildItem(
        ctx,
        key as ItemKey<K>,
        item,
        enabled:
            bridge != null &&
            bridge.itemsEnabled() &&
            (reorder?.buildDefaultItemDragHandles ?? false),
      ),
    };
  }

  /// The module's half of `buildDefaultDragHandles`: a long-press over
  /// the whole row, or nothing at all.
  static Widget _withDefaultHandle(Widget row, {required bool enabled}) {
    if (!enabled) {
      return row;
    }
    return TreeDelayedDragHandle(child: row);
  }

  /// Re-wraps the tree layer's key-typed proxy hook into the module's
  /// kind-paired one. That hook hands back a `SecKey<K>`, which is not a
  /// type a caller can name.
  Widget _buildDragProxy(BuildContext ctx, SecKey<K> key, Widget? rowChild) {
    final config = reorder!;
    final node = controller.treeController.getNodeData(key);
    if (node != null && key is SectionKey<K>) {
      final data = node.data;
      final builder = config.sectionDragProxyBuilder;
      if (builder != null && data is SectionPayload<Section, Item>) {
        return builder(ctx, _sectionView(key, data.value), rowChild);
      }
    } else if (node != null && key is ItemKey<K>) {
      final data = node.data;
      final builder = config.itemDragProxyBuilder;
      if (builder != null && data is ItemPayload<Section, Item>) {
        final view = _itemView(key, data.value);
        if (view != null) {
          return builder(ctx, view, rowChild);
        }
      }
    }
    // Reproduce the package default for the kind that supplied no
    // builder. The tree layer's own default branch is unreachable once
    // ANY builder is installed, so without this, customising one kind
    // would silently render the other at full opacity.
    if (rowChild == null) {
      return const SizedBox.shrink();
    }
    return Opacity(opacity: 0.9, child: rowChild);
  }

  SectionView<K, Section, Item> _sectionView(
    SectionKey<K> key,
    Section section,
  ) {
    final treeController = controller.treeController;
    return SectionView<K, Section, Item>(
      key: key.value,
      section: section,
      itemCount: treeController.getChildCount(key),
      isExpanded: treeController.isExpanded(key),
      isCollapsible: collapsible,
      controller: controller,
    );
  }

  ItemView<K, Section, Item>? _itemView(ItemKey<K> key, Item item) {
    final treeController = controller.treeController;
    final parent = treeController.getParent(key);
    if (parent is! SectionKey<K>) {
      return null;
    }
    final sectionPayload = treeController.getNodeData(parent);
    if (sectionPayload == null ||
        sectionPayload.data is! SectionPayload<Section, Item>) {
      return null;
    }
    return ItemView<K, Section, Item>(
      key: key.value,
      item: item,
      sectionKey: parent.value,
      section: (sectionPayload.data as SectionPayload<Section, Item>).value,
      indexInSection: treeController.getIndexInParent(key),
      controller: controller,
    );
  }

  Widget _buildItem(
    BuildContext ctx,
    ItemKey<K> key,
    Item item, {
    required bool enabled,
  }) {
    // Once, not twice: resolving a view costs a parent lookup plus an
    // O(siblings) index scan, and this runs per visible row per build.
    final view = _itemView(key, item);
    if (view == null) {
      return const SizedBox.shrink();
    }
    return _withDefaultHandle(itemBuilder(ctx, view), enabled: enabled);
  }
}
