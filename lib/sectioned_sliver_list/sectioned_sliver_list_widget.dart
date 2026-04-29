/// Header + items convenience sliver, built on top of [SliverTree].
///
/// Models a strict 2-level structure (sections containing items, items
/// have no children) with separate types and builders for each level,
/// animated insert/remove/reparent, sticky headers, and an optional
/// external controller.
///
/// Type parameters: `<SKey, IKey, Section, Item>`. Section and item key
/// domains are kept disjoint internally even when `SKey == IKey`. For
/// readability you can alias at the call site:
///
/// ```dart
/// typedef MySectionedList = SectionedSliverList<String, String, Folder, File>;
/// ```
///
/// Two constructors:
///
/// - default — declarative `SectionInput` list:
///   ```dart
///   SectionedSliverList<String, String, Folder, File>(
///     sections: [
///       SectionInput(key: 'docs', section: docsFolder, items: [...]),
///       SectionInput(key: 'pics', section: picsFolder, items: [...]),
///     ],
///     headerBuilder: (ctx, s) => FolderHeader(s.section),
///     itemBuilder: (ctx, i) => FileTile(i.item),
///   )
///   ```
///
/// - `.grouped` — from `Map<Section, List<Item>>`:
///   ```dart
///   SectionedSliverList.grouped(
///     sections: files.groupListsBy((f) => f.folder),
///     sectionKeyOf: (folder) => folder.id,
///     itemKeyOf: (file) => file.id,
///     headerBuilder: ..., itemBuilder: ...,
///   )
///   ```
///
/// Source-of-truth rule: when both `sections` and `controller` are
/// supplied, the prop is authoritative on every rebuild — controller
/// mutations between rebuilds persist, but a parent rebuild with new
/// `sections` re-diffs against that new value (matches `TextField`
/// semantics with `TextEditingController`).
library;

import 'package:flutter/widgets.dart';

import '../sliver_tree/sliver_tree.dart';
import '_internal_keys.dart';
import 'section_input.dart';
import 'sectioned_list_controller.dart';
import 'views.dart';

/// Builds a header widget for a visible section.
typedef SectionHeaderBuilder<SKey, IKey, Section, Item> =
    Widget Function(
      BuildContext context,
      SectionView<SKey, IKey, Section, Item> view,
    );

/// Builds a row widget for a visible item.
typedef SectionItemBuilder<SKey, IKey, Section, Item> =
    Widget Function(
      BuildContext context,
      ItemView<SKey, IKey, Section, Item> view,
    );

class SectionedSliverList<SKey, IKey, Section, Item> extends StatefulWidget {
  /// Declarative form: a list of `SectionInput`s.
  const SectionedSliverList({
    required Iterable<SectionInput<SKey, IKey, Section, Item>> sections,
    required this.headerBuilder,
    required this.itemBuilder,
    this.controller,
    this.collapsible = true,
    this.stickyHeaders = true,
    this.preserveExpansion = true,
    this.hideEmptySections = false,
    this.initiallyExpanded = true,
    this.initialSectionExpansion,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.itemIndent = 0.0,
    super.key,
  }) : _sections = sections,
       _groupedSections = null,
       _sectionKeyOf = null,
       _itemKeyOf = null;

  /// `groupListsBy`-shaped form. `sections` is a
  /// `Map<Section, List<Item>>`; iteration order = render order.
  ///
  /// Section payload identity should be aligned with `sectionKeyOf`
  /// (use Equatable, freezed, or hand-rolled `==`/`hashCode`). Two
  /// distinct map entries that produce the same `sectionKeyOf` result
  /// will assert in debug; release builds use the last-iterated payload.
  const SectionedSliverList.grouped({
    required Map<Section, List<Item>> sections,
    required SKey Function(Section) sectionKeyOf,
    required IKey Function(Item) itemKeyOf,
    required this.headerBuilder,
    required this.itemBuilder,
    this.controller,
    this.collapsible = true,
    this.stickyHeaders = true,
    this.preserveExpansion = true,
    this.hideEmptySections = false,
    this.initiallyExpanded = true,
    this.initialSectionExpansion,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.itemIndent = 0.0,
    super.key,
  }) : _sections = null,
       _groupedSections = sections,
       _sectionKeyOf = sectionKeyOf,
       _itemKeyOf = itemKeyOf;

  // Constructor-mode storage.
  final Iterable<SectionInput<SKey, IKey, Section, Item>>? _sections;
  final Map<Section, List<Item>>? _groupedSections;
  final SKey Function(Section)? _sectionKeyOf;
  final IKey Function(Item)? _itemKeyOf;

  /// Optional external controller. When null, the widget creates and
  /// owns one internally.
  final SectionedListController<SKey, IKey, Section, Item>? controller;

  /// Builds the header for each section.
  final SectionHeaderBuilder<SKey, IKey, Section, Item> headerBuilder;

  /// Builds each item row.
  final SectionItemBuilder<SKey, IKey, Section, Item> itemBuilder;

  /// Whether sections can be expanded/collapsed.
  ///
  /// `true` (default): sections start expanded according to
  /// [initiallyExpanded]/[initialSectionExpansion] and respond to
  /// `expand`/`collapse`/`toggle`. `false`: all sections are kept
  /// expanded; `expand`/`collapse` calls become no-ops at the widget
  /// level (the controller still allows them programmatically).
  final bool collapsible;

  /// Whether section headers stick to the top while their items scroll.
  /// Maps to the underlying `SliverTree.maxStickyDepth`.
  final bool stickyHeaders;

  /// When true, the underlying tree remembers expansion state across
  /// remove/re-add cycles. Ignored when an external [controller] is
  /// supplied; the controller's value wins.
  final bool preserveExpansion;

  /// When true, sections with zero items are filtered out of the
  /// declarative input before the diff runs. The controller is
  /// unaffected.
  final bool hideEmptySections;

  /// Default initial-expansion state for newly synced sections, used
  /// when [initialSectionExpansion] is null or returns null for the
  /// section.
  final bool initiallyExpanded;

  /// Per-section initial expansion override. Returning non-null wins
  /// over [initiallyExpanded].
  final bool? Function(SKey key, Section section)? initialSectionExpansion;

  /// Animation duration for expand/collapse and add/remove.
  /// Ignored when an external [controller] is supplied.
  final Duration animationDuration;

  /// Animation curve. Ignored when an external [controller] is supplied.
  final Curve animationCurve;

  /// Visual indent for items under headers, in logical pixels.
  final double itemIndent;

  @override
  State<SectionedSliverList<SKey, IKey, Section, Item>> createState() {
    return SectionedSliverListState<SKey, IKey, Section, Item>();
  }
}

class SectionedSliverListState<SKey, IKey, Section, Item>
    extends State<SectionedSliverList<SKey, IKey, Section, Item>>
    with TickerProviderStateMixin {
  SectionedListController<SKey, IKey, Section, Item>? _internalController;
  late SectionedListController<SKey, IKey, Section, Item> _activeController;

  /// The active controller — either the externally supplied one or the
  /// internal one this widget created. Stable for the widget's lifetime
  /// unless `widget.controller` is reassigned across rebuilds.
  SectionedListController<SKey, IKey, Section, Item> get controller {
    return _activeController;
  }

  @override
  void initState() {
    super.initState();
    _adoptController();
    _sync(animate: false, isFirstSync: true);
  }

  @override
  void didUpdateWidget(
    SectionedSliverList<SKey, IKey, Section, Item> oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      _activeController.debugUnbindWidget();
      if (_internalController != null) {
        _internalController!.dispose();
        _internalController = null;
      }
      _adoptController();
      _sync(animate: true, isFirstSync: true);
      return;
    }

    if (widget.controller == null) {
      // Internally owned: propagate animation params.
      if (oldWidget.animationDuration != widget.animationDuration) {
        _activeController.animationDuration = widget.animationDuration;
      }
      if (oldWidget.animationCurve != widget.animationCurve) {
        _activeController.animationCurve = widget.animationCurve;
      }
      if (oldWidget.preserveExpansion != widget.preserveExpansion) {
        _activeController.preserveExpansion = widget.preserveExpansion;
      }
    } else {
      // External controller is authoritative for state-shape config.
      _assertNoConflictingConfig();
    }

    _sync(animate: true, isFirstSync: false);
  }

  void _adoptController() {
    final external = widget.controller;
    if (external != null) {
      _assertNoConflictingConfig();
      _activeController = external;
    } else {
      _internalController = SectionedListController<SKey, IKey, Section, Item>(
        vsync: this,
        animationDuration: widget.animationDuration,
        animationCurve: widget.animationCurve,
        preserveExpansion: widget.preserveExpansion,
      );
      _activeController = _internalController!;
    }
    _activeController.debugBindWidget();
  }

  void _assertNoConflictingConfig() {
    assert(() {
      const defaultDuration = Duration(milliseconds: 300);
      final defaultCurve = Curves.easeInOut;
      const defaultPreserve = true;
      final hasNonDefault =
          widget.animationDuration != defaultDuration ||
          widget.animationCurve != defaultCurve ||
          widget.preserveExpansion != defaultPreserve;
      if (hasNonDefault) {
        debugPrint(
          "SectionedSliverList: animation/preserveExpansion params on the "
          "widget are ignored when an external controller is supplied. "
          "Configure these on the controller instead.",
        );
      }
      return true;
    }());
  }

  /// Builds the normalized `SectionInput` list from whichever
  /// constructor mode is active, applying the `hideEmptySections`
  /// filter if requested.
  List<SectionInput<SKey, IKey, Section, Item>> _normalizedSections() {
    final List<SectionInput<SKey, IKey, Section, Item>> raw;
    if (widget._sections != null) {
      raw = widget._sections!.toList(growable: false);
    } else {
      raw = _normalizeGrouped();
    }
    if (!widget.hideEmptySections) {
      return raw;
    }
    return <SectionInput<SKey, IKey, Section, Item>>[
      for (final s in raw)
        if (s.items.isNotEmpty) s,
    ];
  }

  List<SectionInput<SKey, IKey, Section, Item>> _normalizeGrouped() {
    final map = widget._groupedSections!;
    final keyOf = widget._sectionKeyOf!;
    final itemKeyOf = widget._itemKeyOf!;
    final result = <SectionInput<SKey, IKey, Section, Item>>[];
    final seenSectionKeys = <SKey>{};
    for (final entry in map.entries) {
      final section = entry.key;
      final sKey = keyOf(section);
      if (!seenSectionKeys.add(sKey)) {
        assert(
          false,
          "SectionedSliverList.grouped: two map entries produced the same "
          "section key '$sKey'. Section payload equality must be aligned "
          "with sectionKeyOf (use Equatable, freezed, or override "
          "==/hashCode), or use the default constructor with explicit "
          "SectionInputs.",
        );
        // Release fallback: replace prior payload with the latest. Find
        // and drop the earlier entry.
        result.removeWhere((s) => s.key == sKey);
      }
      result.add(
        SectionInput<SKey, IKey, Section, Item>(
          key: sKey,
          section: section,
          items: <ItemInput<IKey, Item>>[
            for (final item in entry.value)
              ItemInput<IKey, Item>(key: itemKeyOf(item), item: item),
          ],
        ),
      );
    }
    return result;
  }

  void _sync({required bool animate, required bool isFirstSync}) {
    final knownSections = isFirstSync
        ? <SKey>{}
        : _activeController.sections.toSet();
    final desired = _normalizedSections();
    _activeController.setSections(desired, animate: animate);

    // Per-section initial expansion: applied to sections that are new
    // in this sync (i.e., not in knownSections). Wraps the loop in
    // runBatch to coalesce notifications.
    if (widget.collapsible) {
      _applyInitialExpansion(knownSections, desired, animate: animate);
    } else {
      // Non-collapsible: keep everything expanded regardless of the
      // initial-expansion config.
      _activeController.expandAll(animate: animate);
    }
  }

  void _applyInitialExpansion(
    Set<SKey> knownSections,
    List<SectionInput<SKey, IKey, Section, Item>> desired, {
    required bool animate,
  }) {
    _activeController.runBatch(() {
      for (final input in desired) {
        if (knownSections.contains(input.key)) {
          continue;
        }
        if (!_activeController.hasSection(input.key)) {
          continue;
        }
        final shouldExpand = _resolveInitialExpansion(input);
        if (shouldExpand && !_activeController.isExpanded(input.key)) {
          _activeController.expandSection(input.key, animate: animate);
        } else if (!shouldExpand && _activeController.isExpanded(input.key)) {
          _activeController.collapseSection(input.key, animate: animate);
        }
      }
    });
  }

  bool _resolveInitialExpansion(SectionInput<SKey, IKey, Section, Item> input) {
    final override = widget.initialSectionExpansion?.call(
      input.key,
      input.section,
    );
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
    return _IndentApplier<SKey, IKey, Section, Item>(
      controller: _activeController,
      itemIndent: widget.itemIndent,
      child: SliverTree<SecKey<SKey, IKey>, SecPayload<Section, Item>>(
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
                SectionView<SKey, IKey, Section, Item>(
                  key: (key as SectionKey<SKey, IKey>).value,
                  section: section,
                  itemCount: treeController.getChildCount(key),
                  isExpanded: treeController.isExpanded(key),
                  isCollapsible: widget.collapsible,
                  controller: _activeController,
                ),
              ),
            ItemPayload<Section, Item>(value: final item) => _buildItem(
              ctx,
              key as ItemKey<SKey, IKey>,
              item,
            ),
          };
        },
      ),
    );
  }

  Widget _buildItem(BuildContext ctx, ItemKey<SKey, IKey> key, Item item) {
    final treeController = _activeController.treeController;
    final parent = treeController.getParent(key);
    if (parent is! SectionKey<SKey, IKey>) {
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
      ItemView<SKey, IKey, Section, Item>(
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

/// Inserts the visual `itemIndent` into the underlying [TreeController]
/// without exposing `indentWidth` mutations on the controller. Items
/// (depth 1) get `itemIndent` of horizontal indent; headers (depth 0)
/// get zero.
class _IndentApplier<SKey, IKey, Section, Item> extends StatefulWidget {
  const _IndentApplier({
    required this.controller,
    required this.itemIndent,
    required this.child,
  });

  final SectionedListController<SKey, IKey, Section, Item> controller;
  final double itemIndent;
  final Widget child;

  @override
  State<_IndentApplier<SKey, IKey, Section, Item>> createState() {
    return _IndentApplierState<SKey, IKey, Section, Item>();
  }
}

class _IndentApplierState<SKey, IKey, Section, Item>
    extends State<_IndentApplier<SKey, IKey, Section, Item>> {
  @override
  void initState() {
    super.initState();
    widget.controller.treeController.indentWidth = widget.itemIndent;
  }

  @override
  void didUpdateWidget(_IndentApplier<SKey, IKey, Section, Item> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemIndent != widget.itemIndent ||
        oldWidget.controller != widget.controller) {
      widget.controller.treeController.indentWidth = widget.itemIndent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
